import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/adaptive_suggestion.dart';

/// Local persistence for [AdaptiveHabitSuggestion] metadata, mirroring the
/// habit storage pattern. Suggestion records are kept separate from habit
/// JSON so old habit storage stays valid unchanged.
class AdaptiveSuggestionStorage {
  static const _suggestionsKey = 'adaptive_suggestions';

  Future<List<AdaptiveHabitSuggestion>> loadSuggestions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_suggestionsKey);
    if (raw == null) return [];

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(AdaptiveHabitSuggestion.fromJson)
          .whereType<AdaptiveHabitSuggestion>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveSuggestions(
    List<AdaptiveHabitSuggestion> suggestions,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(suggestions.map((s) => s.toJson()).toList());
    await prefs.setString(_suggestionsKey, encoded);
  }
}
