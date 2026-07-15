import 'package:flutter/material.dart';

/// Corner-radius tokens for cards, buttons, sheets, and inputs.
class AppRadii {
  const AppRadii._();

  static const double small = 8;
  static const double medium = 12;
  static const double large = 16;
  static const double extraLarge = 24;
  static const double pill = 999;

  static const BorderRadius smallRadius = BorderRadius.all(
    Radius.circular(small),
  );
  static const BorderRadius mediumRadius = BorderRadius.all(
    Radius.circular(medium),
  );
  static const BorderRadius largeRadius = BorderRadius.all(
    Radius.circular(large),
  );
  static const BorderRadius extraLargeRadius = BorderRadius.all(
    Radius.circular(extraLarge),
  );
  static const BorderRadius pillRadius = BorderRadius.all(
    Radius.circular(pill),
  );

  static const BorderRadius sheetTopRadius = BorderRadius.only(
    topLeft: Radius.circular(extraLarge),
    topRight: Radius.circular(extraLarge),
  );
}
