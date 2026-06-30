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

  /// Optional easier version of the habit suggested by the AI.
  final String? minimumVersion;

  /// Whether the AI suggests tracking as binary or quantitative.
  final HabitTrackingType trackingType;

  /// AI-suggested daily target for quantitative habits. Null for binary.
  final double? targetValue;

  /// AI-suggested unit label (e.g. "L", "min"). Null for binary.
  final String? unit;

  const HabitSuggestion({
    required this.title,
    required this.reason,
    required this.scheduledTime,
    required this.icon,
    this.weekdays = const [1, 2, 3, 4, 5, 6, 7],
    this.requiredDaysPerWeek,
    this.minimumVersion,
    this.trackingType = HabitTrackingType.binary,
    this.targetValue,
    this.unit,
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
    minimumVersion: minimumVersion,
    trackingType: trackingType,
    targetValue: targetValue,
    unit: unit,
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
      minimumVersion: minimumVersion,
      trackingType: trackingType,
      targetValue: targetValue,
      unit: unit,
    );
  }
}
