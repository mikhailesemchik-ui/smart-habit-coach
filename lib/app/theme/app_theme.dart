import 'package:flutter/material.dart';

/// App-wide ThemeData, extracted from the inline definitions previously in
/// `app.dart`. Behavior-neutral: preserves the existing seed color and
/// Material 3 setup exactly.
class AppTheme {
  const AppTheme._();

  static const Color seedColor = Colors.teal;

  static ThemeData light() {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: seedColor),
      useMaterial3: true,
    );
  }

  static ThemeData dark() {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    );
  }
}
