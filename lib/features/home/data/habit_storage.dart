import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/storage/local_namespace_resolver.dart';
import '../domain/habit.dart';

class HabitStorage {
  static const _habitsBaseKey = 'habits';

  final LocalNamespaceResolver _namespaceResolver;

  HabitStorage({LocalNamespaceResolver? namespaceResolver})
    : _namespaceResolver = namespaceResolver ?? const LocalNamespaceResolver();

  /// Loads all valid habit records. Each JSON list entry is decoded
  /// independently — a single malformed entry is skipped rather than
  /// discarding every other valid record. Returns `null` only when the
  /// top-level stored value itself is missing, not a list, or not valid
  /// JSON (matching this method's existing "no usable data" contract), or
  /// when no local namespace is currently available.
  Future<List<Habit>?> loadHabits() async {
    final result = _namespaceResolver.resolveKey(_habitsBaseKey);
    if (!result.isAvailable) return null;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(result.key!);
    if (raw == null) return null;

    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return null;
    }
    if (decoded is! List) return null;

    var skipped = 0;
    final habits = <Habit>[];
    for (final item in decoded) {
      if (item is! Map<String, dynamic>) {
        skipped++;
        continue;
      }
      try {
        habits.add(Habit.fromJson(item));
      } catch (_) {
        skipped++;
      }
    }
    if (skipped > 0) {
      debugPrint('HabitStorage: skipped $skipped malformed habit record(s)');
    }
    return habits;
  }

  /// Persists [habits]. Throws a [StateError] if no local namespace is
  /// currently available — silently dropping a save would be a silent
  /// data-loss risk, so callers must not be able to invoke this before an
  /// identity is established.
  Future<void> saveHabits(List<Habit> habits) async {
    final result = _namespaceResolver.resolveKey(_habitsBaseKey);
    if (!result.isAvailable) {
      throw StateError('HabitStorage.saveHabits: no local namespace available');
    }
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(habits.map((habit) => habit.toJson()).toList());
    await prefs.setString(result.key!, encoded);
  }
}
