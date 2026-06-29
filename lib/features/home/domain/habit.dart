import 'package:flutter/material.dart';

import 'date_key.dart';
import 'habit_icons.dart';

enum HabitStatus { active, paused, archived }

enum HabitCompletionStatus { none, minimum, full }

HabitStatus _statusFromString(Object? raw) {
  if (raw == 'paused') return HabitStatus.paused;
  if (raw == 'archived') return HabitStatus.archived;
  return HabitStatus.active;
}

class Habit {
  final String id;
  final String title;
  final String scheduledTime;
  final IconData icon;
  final Set<String> completedDates;

  /// Dates on which this habit was completed at minimum level (not full).
  /// A date cannot appear in both [completedDates] and [minimumCompletedDates].
  final Set<String> minimumCompletedDates;

  /// ISO weekdays on which this habit is scheduled (1 = Monday … 7 = Sunday).
  /// All seven days means "every day". Missing from old JSON defaults to all seven.
  final List<int> weekdays;

  final HabitStatus status;

  /// Local date (yyyy-MM-dd) from which this habit became inactive.
  /// Set when pausing; cleared when resuming or archiving.
  final String? pausedFromDate;

  /// Easier version of the habit for difficult days (optional).
  /// null or blank means no minimum version is configured.
  final String? minimumVersion;

  const Habit({
    required this.id,
    required this.title,
    required this.scheduledTime,
    required this.icon,
    this.completedDates = const {},
    this.minimumCompletedDates = const {},
    this.weekdays = const [1, 2, 3, 4, 5, 6, 7],
    this.status = HabitStatus.active,
    this.pausedFromDate,
    this.minimumVersion,
  });

  bool get isActive => status == HabitStatus.active;

  bool get isCompletedToday => completedDates.contains(todayKey());

  bool isCompletedOn(String key) => completedDates.contains(key);

  bool isScheduledFor(DateTime date) => weekdays.contains(date.weekday);

  /// True when this habit has a non-blank minimum version configured.
  bool get hasMinimumVersion =>
      minimumVersion != null && minimumVersion!.trim().isNotEmpty;

  /// Returns the completion state for a given date key.
  HabitCompletionStatus completionStatusFor(String key) {
    if (completedDates.contains(key)) return HabitCompletionStatus.full;
    if (minimumCompletedDates.contains(key)) {
      return HabitCompletionStatus.minimum;
    }
    return HabitCompletionStatus.none;
  }

  /// Returns a copy with the completion status for [key] set to [status].
  /// A date can only exist in one set at a time; the other set is updated
  /// accordingly.
  Habit setCompletionStatus(String key, HabitCompletionStatus status) {
    final newFull = Set<String>.of(completedDates);
    final newMin = Set<String>.of(minimumCompletedDates);
    switch (status) {
      case HabitCompletionStatus.full:
        newFull.add(key);
        newMin.remove(key);
      case HabitCompletionStatus.minimum:
        newMin.add(key);
        newFull.remove(key);
      case HabitCompletionStatus.none:
        newFull.remove(key);
        newMin.remove(key);
    }
    return copyWith(completedDates: newFull, minimumCompletedDates: newMin);
  }

  /// Toggles full completion for [key]. If the date was minimally completed,
  /// upgrading to full removes it from [minimumCompletedDates].
  Habit toggleDate(String key) {
    final newFull = Set<String>.of(completedDates);
    final newMin = Set<String>.of(minimumCompletedDates);
    if (!newFull.remove(key)) {
      newFull.add(key);
      newMin.remove(key);
    }
    return copyWith(completedDates: newFull, minimumCompletedDates: newMin);
  }

  // Sentinel so copyWith can explicitly clear nullable fields.
  static const Object _omit = Object();

  Habit copyWith({
    Set<String>? completedDates,
    Set<String>? minimumCompletedDates,
    List<int>? weekdays,
    HabitStatus? status,
    Object? pausedFromDate = _omit,
    Object? minimumVersion = _omit,
  }) {
    return Habit(
      id: id,
      title: title,
      scheduledTime: scheduledTime,
      icon: icon,
      completedDates: completedDates ?? this.completedDates,
      minimumCompletedDates:
          minimumCompletedDates ?? this.minimumCompletedDates,
      weekdays: weekdays ?? this.weekdays,
      status: status ?? this.status,
      pausedFromDate: identical(pausedFromDate, _omit)
          ? this.pausedFromDate
          : pausedFromDate as String?,
      minimumVersion: identical(minimumVersion, _omit)
          ? this.minimumVersion
          : minimumVersion as String?,
    );
  }

  /// Returns a paused copy. [today] is yyyy-MM-dd. Preserves any existing
  /// pausedFromDate so that re-pausing does not overwrite the original boundary.
  Habit asPaused(String today) => copyWith(
    status: HabitStatus.paused,
    pausedFromDate: pausedFromDate ?? today,
  );

  /// Returns an active copy with the pause boundary cleared.
  Habit asActive() =>
      copyWith(status: HabitStatus.active, pausedFromDate: null);

  /// Returns an archived copy. Preserves an existing [pausedFromDate] so that
  /// paused→archived transitions keep the original boundary.
  Habit asArchived(String today) => copyWith(
    status: HabitStatus.archived,
    pausedFromDate: pausedFromDate ?? today,
  );

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'scheduledTime': scheduledTime,
      'iconId': habitIconToId(icon),
      'completedDates': completedDates.toList(),
      'minimumCompletedDates': minimumCompletedDates.toList(),
      'weekdays': weekdays,
      'status': status.name,
      if (pausedFromDate != null) 'pausedFromDate': pausedFromDate,
      if (minimumVersion != null) 'minimumVersion': minimumVersion,
    };
  }

  factory Habit.fromJson(Map<String, dynamic> json) {
    return Habit(
      id: json['id'] as String,
      title: json['title'] as String,
      scheduledTime: json['scheduledTime'] as String,
      icon: habitIconFromId(json['iconId'] as String),
      completedDates: _readCompletedDates(json),
      minimumCompletedDates: _readStringSet(json['minimumCompletedDates']),
      weekdays: _readWeekdays(json),
      status: _statusFromString(json['status']),
      pausedFromDate: json['pausedFromDate'] as String?,
      minimumVersion: json['minimumVersion'] as String?,
    );
  }

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

  static Set<String> _readStringSet(Object? raw) {
    if (raw is! List) return {};
    return raw.whereType<String>().toSet();
  }
}
