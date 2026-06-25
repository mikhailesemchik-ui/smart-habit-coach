import 'package:flutter/material.dart';

import '../../home/domain/habit.dart';

class HabitSuggestion {
  final String title;
  final String reason;
  final String scheduledTime;
  final IconData icon;

  const HabitSuggestion({
    required this.title,
    required this.reason,
    required this.scheduledTime,
    required this.icon,
  });

  Habit toHabit() {
    return Habit(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      scheduledTime: scheduledTime,
      icon: icon,
    );
  }
}
