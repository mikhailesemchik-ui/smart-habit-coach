import 'package:flutter/material.dart';

import 'habit_suggestion.dart';

const _waterKeywords = ['water', 'hydrate', 'hydration'];
const _readingKeywords = ['read', 'reading', 'book'];
const _activityKeywords = [
  'walk',
  'walking',
  'exercise',
  'workout',
  'run',
  'running',
];
const _sleepKeywords = ['sleep', 'rest', 'bedtime'];

/// Deterministic, rule-based stand-in for a real AI suggestion service.
/// Swap the body of this function for an API call later without
/// changing any of its callers.
HabitSuggestion generateHabitSuggestion(String goalDescription) {
  final normalized = goalDescription.toLowerCase();

  if (_matchesAny(normalized, _waterKeywords)) {
    return const HabitSuggestion(
      title: 'Drink more water',
      reason: 'Staying hydrated boosts energy and focus throughout the day.',
      scheduledTime: '09:00 AM',
      icon: Icons.local_drink_outlined,
    );
  }

  if (_matchesAny(normalized, _readingKeywords)) {
    return const HabitSuggestion(
      title: 'Read for 20 minutes',
      reason:
          'A short daily reading habit builds knowledge and helps you unwind.',
      scheduledTime: '08:00 PM',
      icon: Icons.menu_book_outlined,
    );
  }

  if (_matchesAny(normalized, _activityKeywords)) {
    return const HabitSuggestion(
      title: 'Go for a 20-minute walk',
      reason: 'Regular movement supports physical and mental health.',
      scheduledTime: '06:00 PM',
      icon: Icons.directions_walk_outlined,
    );
  }

  if (_matchesAny(normalized, _sleepKeywords)) {
    return const HabitSuggestion(
      title: 'Keep a consistent sleep schedule',
      reason: 'Consistent sleep improves mood, focus, and long-term health.',
      scheduledTime: '10:00 PM',
      icon: Icons.bedtime_outlined,
    );
  }

  return const HabitSuggestion(
    title: 'Build a new habit',
    reason:
        'Starting small and staying consistent is the best way to make progress.',
    scheduledTime: '09:00 AM',
    icon: Icons.self_improvement_outlined,
  );
}

bool _matchesAny(String text, List<String> keywords) {
  return keywords.any((keyword) => text.contains(keyword));
}
