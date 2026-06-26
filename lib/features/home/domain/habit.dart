import 'package:flutter/material.dart';

import 'date_key.dart';
import 'habit_icons.dart';

class Habit {
  final String id;
  final String title;
  final String scheduledTime;
  final IconData icon;
  final Set<String> completedDates;

  /// ISO weekdays on which this habit is scheduled (1 = Monday … 7 = Sunday).
  /// All seven days means "every day". Missing from old JSON defaults to all seven.
  final List<int> weekdays;

  const Habit({
    required this.id,
    required this.title,
    required this.scheduledTime,
    required this.icon,
    this.completedDates = const {},
    this.weekdays = const [1, 2, 3, 4, 5, 6, 7],
  });

  bool get isCompletedToday => completedDates.contains(todayKey());

  bool isCompletedOn(String dateKey) => completedDates.contains(dateKey);

  bool isScheduledFor(DateTime date) => weekdays.contains(date.weekday);

  Habit toggleDate(String dateKey) {
    final updated = Set<String>.of(completedDates);
    if (!updated.remove(dateKey)) {
      updated.add(dateKey);
    }
    return copyWith(completedDates: updated);
  }

  Habit copyWith({Set<String>? completedDates, List<int>? weekdays}) {
    return Habit(
      id: id,
      title: title,
      scheduledTime: scheduledTime,
      icon: icon,
      completedDates: completedDates ?? this.completedDates,
      weekdays: weekdays ?? this.weekdays,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'scheduledTime': scheduledTime,
      'iconId': habitIconToId(icon),
      'completedDates': completedDates.toList(),
      'weekdays': weekdays,
    };
  }

  factory Habit.fromJson(Map<String, dynamic> json) {
    return Habit(
      id: json['id'] as String,
      title: json['title'] as String,
      scheduledTime: json['scheduledTime'] as String,
      icon: habitIconFromId(json['iconId'] as String),
      completedDates: _readCompletedDates(json),
      weekdays: _readWeekdays(json),
    );
  }

  /// Normalises the stored weekdays: valid range 1–7, unique, sorted.
  /// Falls back to all seven days when the field is absent or produces an
  /// empty result (backward-compatible with old JSON).
  static List<int> _readWeekdays(Map<String, dynamic> json) {
    final raw = json['weekdays'];
    if (raw is List) {
      final days =
          raw.whereType<int>().where((d) => d >= 1 && d <= 7).toSet().toList()
            ..sort();
      if (days.isNotEmpty) return days;
    }
    return const [1, 2, 3, 4, 5, 6, 7];
  }

  static Set<String> _readCompletedDates(Map<String, dynamic> json) {
    final rawDates = json['completedDates'];
    if (rawDates is List) {
      return rawDates.map((date) => date as String).toSet();
    }
    if (json['isCompleted'] == true) {
      return {todayKey()};
    }
    return {};
  }
}
