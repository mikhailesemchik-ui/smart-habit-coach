import 'package:flutter/material.dart';

import 'date_key.dart';
import 'habit_icons.dart';

enum HabitStatus { active, paused, archived }

enum HabitCompletionStatus { none, minimum, full }

enum HabitSkipReason { noTime, forgot, tooTired, tooDifficult, other }

/// Reason why a quantitative habit was only partially completed.
enum HabitPartialReason {
  noTime,
  tooTired,
  targetTooDifficult,
  forgotToContinue,
  other,
}

/// Whether a habit tracks done/not-done or a daily numeric amount.
enum HabitTrackingType { binary, quantitative }

HabitStatus _statusFromString(Object? raw) {
  if (raw == 'paused') return HabitStatus.paused;
  if (raw == 'archived') return HabitStatus.archived;
  return HabitStatus.active;
}

HabitSkipReason? habitSkipReasonFromString(Object? raw) {
  if (raw is! String) return null;
  for (final reason in HabitSkipReason.values) {
    if (reason.name == raw) return reason;
  }
  return null;
}

String habitSkipReasonLabel(HabitSkipReason reason) {
  return switch (reason) {
    HabitSkipReason.noTime => 'No time',
    HabitSkipReason.forgot => 'Forgot',
    HabitSkipReason.tooTired => 'Too tired',
    HabitSkipReason.tooDifficult => 'Too difficult',
    HabitSkipReason.other => 'Other',
  };
}

HabitPartialReason? habitPartialReasonFromString(Object? raw) {
  if (raw is! String) return null;
  for (final reason in HabitPartialReason.values) {
    if (reason.name == raw) return reason;
  }
  return null;
}

String habitPartialReasonLabel(HabitPartialReason reason) {
  return switch (reason) {
    HabitPartialReason.noTime => 'No time',
    HabitPartialReason.tooTired => 'Too tired',
    HabitPartialReason.targetTooDifficult => 'Target too difficult',
    HabitPartialReason.forgotToContinue => 'Forgot to continue',
    HabitPartialReason.other => 'Other',
  };
}

/// Formats a numeric progress value: whole numbers without decimal point,
/// fractional values to one decimal place.
String habitProgressLabel(double value) {
  if (value % 1 == 0) return value.toInt().toString();
  return value.toStringAsFixed(1);
}

class Habit {
  final String id;
  final String title;
  final String scheduledTime;
  final IconData icon;
  final Set<String> completedDates;

  /// Dates completed at minimum level (not full).
  /// A date cannot appear in both [completedDates] and [minimumCompletedDates].
  final Set<String> minimumCompletedDates;

  /// ISO weekdays on which this habit is scheduled (1 = Monday … 7 = Sunday).
  /// All seven days means "every day". Missing from old JSON defaults to all 7.
  final List<int> weekdays;

  final HabitStatus status;

  /// Local date (yyyy-MM-dd) → reason recorded for a missed scheduled day.
  final Map<String, HabitSkipReason> skipReasons;

  /// Optional free-text notes for skip entries (currently only for "Other").
  final Map<String, String> skipReasonNotes;

  /// Local date (yyyy-MM-dd) from which this habit became inactive.
  final String? pausedFromDate;

  /// Easier version of the habit for difficult days (optional).
  final String? minimumVersion;

  /// Whether this habit is tracked as binary or a daily numeric amount.
  final HabitTrackingType trackingType;

  /// Daily numeric target. Must be > 0 when set. Only used for quantitative.
  final double? targetValue;

  /// Unit label for the daily target (e.g. "L", "min", "steps").
  final String? unit;

  /// Numeric daily progress keyed by yyyy-MM-dd. Stored values are always > 0.
  /// For quantitative habits, [completedDates] is updated automatically when
  /// progress reaches [targetValue].
  final Map<String, double> quantitativeProgress;

  /// Reasons why quantitative progress was only partial (> 0 but < target).
  final Map<String, HabitPartialReason> partialReasons;

  /// Optional notes for partial reason entries (only for "Other").
  final Map<String, String> partialReasonNotes;

  /// Optional free-text notes tied to a specific local date (yyyy-MM-dd).
  /// Notes are independent of completion state and never affect statistics.
  final Map<String, String> completionNotes;

  const Habit({
    required this.id,
    required this.title,
    required this.scheduledTime,
    required this.icon,
    this.completedDates = const {},
    this.minimumCompletedDates = const {},
    this.weekdays = const [1, 2, 3, 4, 5, 6, 7],
    this.status = HabitStatus.active,
    this.skipReasons = const {},
    this.skipReasonNotes = const {},
    this.pausedFromDate,
    this.minimumVersion,
    this.trackingType = HabitTrackingType.binary,
    this.targetValue,
    this.unit,
    this.quantitativeProgress = const {},
    this.partialReasons = const {},
    this.partialReasonNotes = const {},
    this.completionNotes = const {},
  });

  bool get isActive => status == HabitStatus.active;
  bool get isQuantitative => trackingType == HabitTrackingType.quantitative;
  bool get isCompletedToday => completedDates.contains(todayKey());
  bool isCompletedOn(String key) => completedDates.contains(key);
  bool isScheduledFor(DateTime date) => weekdays.contains(date.weekday);

  HabitSkipReason? skipReasonFor(DateTime date) => skipReasons[dateKey(date)];

  String? skipReasonNoteFor(DateTime date) {
    final note = skipReasonNotes[dateKey(date)]?.trim();
    return note == null || note.isEmpty ? null : note;
  }

  HabitPartialReason? partialReasonFor(DateTime date) =>
      partialReasons[dateKey(date)];

  String? partialReasonNoteFor(DateTime date) {
    final note = partialReasonNotes[dateKey(date)]?.trim();
    return note == null || note.isEmpty ? null : note;
  }

  /// Returns the note stored for [date], or null if none.
  String? noteFor(DateTime date) {
    final note = completionNotes[dateKey(date)]?.trim();
    return (note == null || note.isEmpty) ? null : note;
  }

  /// Returns a copy with the note for [date] set.
  /// A null or whitespace-only [note] removes the entry.
  /// Notes do not affect completion, progress, or statistics.
  Habit setNote(DateTime date, String? note) {
    final key = dateKey(date);
    final newNotes = Map<String, String>.of(completionNotes);
    final trimmed = note?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      newNotes.remove(key);
    } else {
      newNotes[key] = trimmed;
    }
    return copyWith(completionNotes: newNotes);
  }

  /// True when this habit has a non-blank minimum version configured.
  bool get hasMinimumVersion =>
      minimumVersion != null && minimumVersion!.trim().isNotEmpty;

  // ── Quantitative helpers ──────────────────────────────────────────────────

  /// Recorded numeric progress for [date]. Returns 0 when nothing is logged.
  double progressFor(DateTime date) => quantitativeProgress[dateKey(date)] ?? 0;

  /// Fraction of target achieved for [date], clamped to [0, 1].
  /// Returns 0 for binary habits or when [targetValue] is unset/zero.
  double progressRatioFor(DateTime date) {
    final target = targetValue;
    if (target == null || target <= 0) return 0;
    return (progressFor(date) / target).clamp(0.0, 1.0);
  }

  /// True when logged progress for [date] meets or exceeds [targetValue].
  bool isTargetReached(DateTime date) {
    final target = targetValue;
    if (target == null || target <= 0) return false;
    return progressFor(date) >= target;
  }

  /// True when quantitative progress for [key] is positive but below target.
  bool hasPartialProgressOn(String key) {
    if (!isQuantitative) return false;
    final v = quantitativeProgress[key] ?? 0;
    final target = targetValue;
    if (target == null || target <= 0) return false;
    return v > 0 && v < target;
  }

  // ── Completion status ─────────────────────────────────────────────────────

  /// Returns the binary completion state for [key].
  /// For quantitative habits [minimum] is never returned — partial progress
  /// is expressed via [hasPartialProgressOn] and [progressFor].
  HabitCompletionStatus completionStatusFor(String key) {
    if (completedDates.contains(key)) return HabitCompletionStatus.full;
    if (!isQuantitative && minimumCompletedDates.contains(key)) {
      return HabitCompletionStatus.minimum;
    }
    return HabitCompletionStatus.none;
  }

  /// Returns a copy with the completion status for [key] set to [status].
  /// A date can only exist in one set at a time.
  Habit setCompletionStatus(String key, HabitCompletionStatus status) {
    final newFull = Set<String>.of(completedDates);
    final newMin = Set<String>.of(minimumCompletedDates);
    final newReasons = Map<String, HabitSkipReason>.of(skipReasons);
    final newNotes = Map<String, String>.of(skipReasonNotes);
    switch (status) {
      case HabitCompletionStatus.full:
        newFull.add(key);
        newMin.remove(key);
        newReasons.remove(key);
        newNotes.remove(key);
      case HabitCompletionStatus.minimum:
        newMin.add(key);
        newFull.remove(key);
        newReasons.remove(key);
        newNotes.remove(key);
      case HabitCompletionStatus.none:
        newFull.remove(key);
        newMin.remove(key);
    }
    return copyWith(
      completedDates: newFull,
      minimumCompletedDates: newMin,
      skipReasons: newReasons,
      skipReasonNotes: newNotes,
    );
  }

  /// Toggles full completion for [key]. Upgrading from minimum to full removes
  /// the minimum entry.
  Habit toggleDate(String key) {
    final newFull = Set<String>.of(completedDates);
    final newMin = Set<String>.of(minimumCompletedDates);
    final newReasons = Map<String, HabitSkipReason>.of(skipReasons);
    final newNotes = Map<String, String>.of(skipReasonNotes);
    if (!newFull.remove(key)) {
      newFull.add(key);
      newMin.remove(key);
      newReasons.remove(key);
      newNotes.remove(key);
    }
    return copyWith(
      completedDates: newFull,
      minimumCompletedDates: newMin,
      skipReasons: newReasons,
      skipReasonNotes: newNotes,
    );
  }

  /// Records numeric progress for [date] on a quantitative habit.
  ///
  /// Rules:
  /// - Negative values are clamped to 0.
  /// - Zero removes the stored entry (and clears full completion).
  /// - Values ≥ [targetValue] mark the date as fully completed in
  ///   [completedDates] and remove any partial/minimum entry.
  /// - Positive values clear any skip reason for the date.
  /// - Returns [this] unchanged for binary habits or unscheduled dates.
  Habit setProgress(DateTime date, double value) {
    if (!isQuantitative || !isScheduledFor(date)) return this;
    final key = dateKey(date);
    final clamped = value < 0 ? 0.0 : value;
    final newProgress = Map<String, double>.of(quantitativeProgress);
    if (clamped == 0) {
      newProgress.remove(key);
    } else {
      newProgress[key] = clamped;
    }
    final newFull = Set<String>.of(completedDates);
    final newMin = Set<String>.of(minimumCompletedDates);
    final newReasons = Map<String, HabitSkipReason>.of(skipReasons);
    final newNotes = Map<String, String>.of(skipReasonNotes);
    final newPartialReasons = Map<String, HabitPartialReason>.of(
      partialReasons,
    );
    final newPartialNotes = Map<String, String>.of(partialReasonNotes);

    final target = targetValue;
    if (target != null && target > 0 && clamped >= target) {
      newFull.add(key);
      newMin.remove(key);
      // Reaching target clears any partial reason.
      newPartialReasons.remove(key);
      newPartialNotes.remove(key);
    } else {
      newFull.remove(key);
      newMin.remove(key);
    }
    if (clamped == 0) {
      // Resetting to zero clears partial reason (allows skip reason instead).
      newPartialReasons.remove(key);
      newPartialNotes.remove(key);
    }
    if (clamped > 0) {
      newReasons.remove(key);
      newNotes.remove(key);
    }
    return copyWith(
      quantitativeProgress: newProgress,
      completedDates: newFull,
      minimumCompletedDates: newMin,
      skipReasons: newReasons,
      skipReasonNotes: newNotes,
      partialReasons: newPartialReasons,
      partialReasonNotes: newPartialNotes,
    );
  }

  Habit setSkipReason(DateTime date, HabitSkipReason? reason, {String? note}) {
    if (!isScheduledFor(date)) return this;
    final key = dateKey(date);
    final newFull = Set<String>.of(completedDates)..remove(key);
    final newMin = Set<String>.of(minimumCompletedDates)..remove(key);
    // Setting a skip reason resets any numeric progress for the date.
    final newProgress = Map<String, double>.of(quantitativeProgress)
      ..remove(key);
    final newReasons = Map<String, HabitSkipReason>.of(skipReasons);
    final newNotes = Map<String, String>.of(skipReasonNotes);

    if (reason == null) {
      newReasons.remove(key);
      newNotes.remove(key);
    } else {
      newReasons[key] = reason;
      if (reason == HabitSkipReason.other) {
        final trimmed = note?.trim();
        if (trimmed == null || trimmed.isEmpty) {
          newNotes.remove(key);
        } else {
          newNotes[key] = trimmed;
        }
      } else {
        newNotes.remove(key);
      }
    }

    return copyWith(
      completedDates: newFull,
      minimumCompletedDates: newMin,
      quantitativeProgress: newProgress,
      skipReasons: newReasons,
      skipReasonNotes: newNotes,
    );
  }

  /// Records the reason why quantitative progress was only partial for [date].
  ///
  /// Only applies when progress is > 0 and < [targetValue]. Does not modify
  /// numeric progress. Pass [reason] == null to clear an existing entry.
  Habit setPartialReason(
    DateTime date,
    HabitPartialReason? reason, {
    String? note,
  }) {
    if (!isQuantitative || !isScheduledFor(date)) return this;
    final key = dateKey(date);
    if (!hasPartialProgressOn(key)) return this;
    final newPartialReasons = Map<String, HabitPartialReason>.of(
      partialReasons,
    );
    final newPartialNotes = Map<String, String>.of(partialReasonNotes);
    if (reason == null) {
      newPartialReasons.remove(key);
      newPartialNotes.remove(key);
    } else {
      newPartialReasons[key] = reason;
      if (reason == HabitPartialReason.other) {
        final trimmed = note?.trim();
        if (trimmed == null || trimmed.isEmpty) {
          newPartialNotes.remove(key);
        } else {
          newPartialNotes[key] = trimmed;
        }
      } else {
        newPartialNotes.remove(key);
      }
    }
    return copyWith(
      partialReasons: newPartialReasons,
      partialReasonNotes: newPartialNotes,
    );
  }

  // Sentinel so copyWith can explicitly clear nullable fields.
  static const Object _omit = Object();

  Habit copyWith({
    Set<String>? completedDates,
    Set<String>? minimumCompletedDates,
    List<int>? weekdays,
    HabitStatus? status,
    Map<String, HabitSkipReason>? skipReasons,
    Map<String, String>? skipReasonNotes,
    Object? pausedFromDate = _omit,
    Object? minimumVersion = _omit,
    HabitTrackingType? trackingType,
    Map<String, double>? quantitativeProgress,
    Object? targetValue = _omit,
    Object? unit = _omit,
    Map<String, HabitPartialReason>? partialReasons,
    Map<String, String>? partialReasonNotes,
    Map<String, String>? completionNotes,
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
      skipReasons: skipReasons ?? this.skipReasons,
      skipReasonNotes: skipReasonNotes ?? this.skipReasonNotes,
      pausedFromDate: identical(pausedFromDate, _omit)
          ? this.pausedFromDate
          : pausedFromDate as String?,
      minimumVersion: identical(minimumVersion, _omit)
          ? this.minimumVersion
          : minimumVersion as String?,
      trackingType: trackingType ?? this.trackingType,
      quantitativeProgress: quantitativeProgress ?? this.quantitativeProgress,
      targetValue: identical(targetValue, _omit)
          ? this.targetValue
          : targetValue as double?,
      unit: identical(unit, _omit) ? this.unit : unit as String?,
      partialReasons: partialReasons ?? this.partialReasons,
      partialReasonNotes: partialReasonNotes ?? this.partialReasonNotes,
      completionNotes: completionNotes ?? this.completionNotes,
    );
  }

  /// Returns a paused copy.
  Habit asPaused(String today) => copyWith(
    status: HabitStatus.paused,
    pausedFromDate: pausedFromDate ?? today,
  );

  /// Returns an active copy with the pause boundary cleared.
  Habit asActive() =>
      copyWith(status: HabitStatus.active, pausedFromDate: null);

  /// Returns an archived copy.
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
      if (skipReasons.isNotEmpty)
        'skipReasons': skipReasons.map(
          (key, value) => MapEntry(key, value.name),
        ),
      if (skipReasonNotes.isNotEmpty) 'skipReasonNotes': skipReasonNotes,
      if (pausedFromDate != null) 'pausedFromDate': pausedFromDate,
      if (minimumVersion != null) 'minimumVersion': minimumVersion,
      if (trackingType != HabitTrackingType.binary)
        'trackingType': trackingType.name,
      if (targetValue != null) 'targetValue': targetValue,
      if (unit != null) 'unit': unit,
      if (quantitativeProgress.isNotEmpty)
        'quantitativeProgress': quantitativeProgress,
      if (partialReasons.isNotEmpty)
        'partialReasons': partialReasons.map(
          (key, value) => MapEntry(key, value.name),
        ),
      if (partialReasonNotes.isNotEmpty)
        'partialReasonNotes': partialReasonNotes,
      if (completionNotes.isNotEmpty) 'completionNotes': completionNotes,
    };
  }

  factory Habit.fromJson(Map<String, dynamic> json) {
    final weekdays = _readWeekdays(json);
    return Habit(
      id: json['id'] as String,
      title: json['title'] as String,
      scheduledTime: json['scheduledTime'] as String,
      icon: habitIconFromId(json['iconId'] as String),
      completedDates: _readCompletedDates(json),
      minimumCompletedDates: _readStringSet(json['minimumCompletedDates']),
      weekdays: weekdays,
      status: _statusFromString(json['status']),
      skipReasons: _readSkipReasons(json['skipReasons'], weekdays),
      skipReasonNotes: _readSkipReasonNotes(json['skipReasonNotes']),
      pausedFromDate: json['pausedFromDate'] as String?,
      minimumVersion: json['minimumVersion'] as String?,
      trackingType: _readTrackingType(json['trackingType']),
      targetValue: _readPositiveDouble(json['targetValue']),
      unit: _readNonEmptyString(json['unit']),
      quantitativeProgress: _readQuantitativeProgress(
        json['quantitativeProgress'],
        weekdays,
      ),
      partialReasons: _readPartialReasons(json['partialReasons'], weekdays),
      partialReasonNotes: _readStringMap(json['partialReasonNotes']),
      completionNotes: _readStringMap(json['completionNotes']),
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
      return rawDates.whereType<String>().toSet();
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

  static Map<String, HabitSkipReason> _readSkipReasons(
    Object? raw,
    List<int> weekdays,
  ) {
    if (raw is! Map) return {};
    final reasons = <String, HabitSkipReason>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      if (key is! String || !_isValidDateKey(key)) continue;
      final date = parseDateKey(key);
      if (!weekdays.contains(date.weekday)) continue;
      final reason = habitSkipReasonFromString(entry.value);
      if (reason == null) continue;
      reasons[key] = reason;
    }
    return reasons;
  }

  static Map<String, String> _readSkipReasonNotes(Object? raw) =>
      _readStringMap(raw);

  static Map<String, String> _readStringMap(Object? raw) {
    if (raw is! Map) return {};
    final notes = <String, String>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is! String || value is! String || !_isValidDateKey(key)) {
        continue;
      }
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) notes[key] = trimmed;
    }
    return notes;
  }

  static Map<String, HabitPartialReason> _readPartialReasons(
    Object? raw,
    List<int> weekdays,
  ) {
    if (raw is! Map) return {};
    final reasons = <String, HabitPartialReason>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      if (key is! String || !_isValidDateKey(key)) continue;
      final date = parseDateKey(key);
      if (!weekdays.contains(date.weekday)) continue;
      final reason = habitPartialReasonFromString(entry.value);
      if (reason == null) continue;
      reasons[key] = reason;
    }
    return reasons;
  }

  static HabitTrackingType _readTrackingType(Object? raw) {
    if (raw == 'quantitative') return HabitTrackingType.quantitative;
    return HabitTrackingType.binary;
  }

  static double? _readPositiveDouble(Object? raw) {
    if (raw is num) {
      final d = raw.toDouble();
      return d > 0 ? d : null;
    }
    return null;
  }

  static String? _readNonEmptyString(Object? raw) {
    if (raw is! String) return null;
    final t = raw.trim();
    return t.isEmpty ? null : t;
  }

  static Map<String, double> _readQuantitativeProgress(
    Object? raw,
    List<int> weekdays,
  ) {
    if (raw is! Map) return {};
    final progress = <String, double>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      if (key is! String || !_isValidDateKey(key)) continue;
      final date = parseDateKey(key);
      if (!weekdays.contains(date.weekday)) continue;
      final value = entry.value;
      if (value is! num) continue;
      final d = value.toDouble();
      if (d <= 0) continue;
      progress[key] = d;
    }
    return progress;
  }

  static bool _isValidDateKey(String key) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(key)) return false;
    try {
      final parsed = parseDateKey(key);
      return dateKey(parsed) == key;
    } catch (_) {
      return false;
    }
  }
}
