import 'package:flutter/material.dart';

const habitIconOptions = <String, IconData>{
  'water': Icons.local_drink_outlined,
  'book': Icons.menu_book_outlined,
  'walk': Icons.directions_walk_outlined,
  'fitness': Icons.fitness_center_outlined,
  'sleep': Icons.bedtime_outlined,
  'mindfulness': Icons.self_improvement_outlined,
};

const _defaultIconId = 'water';

String habitIconToId(IconData icon) {
  for (final entry in habitIconOptions.entries) {
    if (entry.value == icon) return entry.key;
  }
  return _defaultIconId;
}

IconData habitIconFromId(String id) {
  return habitIconOptions[id] ?? habitIconOptions[_defaultIconId]!;
}
