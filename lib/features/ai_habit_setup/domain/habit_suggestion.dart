import 'package:flutter/material.dart';

import '../../home/domain/habit.dart';

class HabitSuggestion {
  final String title;
  final String reason;
  final String scheduledTime;
  final IconData icon;
  final List<int> weekdays;

  /// When non-null, the user must pick exactly this many weekdays before the
  /// suggestion can become a [Habit]. Null means no constraint.
  final int? requiredDaysPerWeek;

  const HabitSuggestion({
    required this.title,
    required this.reason,
    required this.scheduledTime,
    required this.icon,
    this.weekdays = const [1, 2, 3, 4, 5, 6, 7],
    this.requiredDaysPerWeek,
  });

  /// True when the schedule is fully specified and [toHabit] may be called.
  bool get isResolved =>
      requiredDaysPerWeek == null || weekdays.length == requiredDaysPerWeek;

  /// Returns a copy with [days] as the resolved weekday list.
  HabitSuggestion withWeekdays(List<int> days) => HabitSuggestion(
    title: title,
    reason: reason,
    scheduledTime: scheduledTime,
    icon: icon,
    weekdays: days,
    requiredDaysPerWeek: requiredDaysPerWeek,
  );

  /// Converts this suggestion to a [Habit]. Asserts that [isResolved] is true.
  Habit toHabit() {
    assert(isResolved, 'Cannot create a Habit from an unresolved suggestion.');
    return Habit(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      scheduledTime: scheduledTime,
      icon: icon,
      weekdays: weekdays.isEmpty ? const [1, 2, 3, 4, 5, 6, 7] : weekdays,
    );
  }
}
