import 'package:flutter/material.dart';

/// Soft, low-opacity shadow tokens — used sparingly, cards mostly rely on
/// background/surface contrast rather than heavy elevation.
class AppShadows {
  const AppShadows._();

  static const List<BoxShadow> softCard = [
    BoxShadow(color: Color(0x14000000), blurRadius: 16, offset: Offset(0, 6)),
  ];
}
