import 'package:flutter/material.dart';

/// Color tokens for the app's visual direction: calm, premium
/// habit/wellness palette — deep teal/forest green primary, soft mint
/// accents, warm off-white background, coral/red reserved for destructive
/// actions only.
class AppColors {
  const AppColors._();

  // Brand
  static const Color primary = Color(0xFF1B6B5A);
  static const Color primaryContainer = Color(0xFFCFE8DE);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color secondary = Color(0xFF6FA98E);

  // Light surfaces
  static const Color background = Color(0xFFF3F6F3);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFE9F1EC);

  // Dark surfaces
  static const Color backgroundDark = Color(0xFF10201B);
  static const Color surfaceDark = Color(0xFF17281F);
  static const Color surfaceMutedDark = Color(0xFF1E332A);

  // Text (light theme)
  static const Color textPrimary = Color(0xFF16211C);
  static const Color textSecondary = Color(0xFF56685F);
  static const Color textMuted = Color(0xFF8A9A92);

  // Text (dark theme)
  static const Color textPrimaryDark = Color(0xFFEAF1EC);
  static const Color textSecondaryDark = Color(0xFFB4C4BB);
  static const Color textMutedDark = Color(0xFF8298A0);

  // Status
  static const Color success = Color(0xFF2E8B57);
  static const Color warning = Color(0xFFC98A2C);
  static const Color danger = Color(0xFFD1483F);
  static const Color dangerContainer = Color(0xFFF6DAD7);

  // Structure
  static const Color outline = Color(0xFFD8E2DC);
  static const Color outlineDark = Color(0xFF2C4038);
}
