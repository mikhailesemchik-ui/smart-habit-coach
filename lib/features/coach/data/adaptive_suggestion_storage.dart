import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/storage/local_namespace_resolver.dart';
import '../domain/adaptive_suggestion.dart';

/// Local persistence for [AdaptiveHabitSuggestion] metadata, mirroring the
/// habit storage pattern. Suggestion records are kept separate from habit
/// JSON so old habit storage stays valid unchanged.
class AdaptiveSuggestionStorage {
  static const _suggestionsBaseKey = 'adaptive_suggestions';

  final LocalNamespaceResolver _namespaceResolver;

  AdaptiveSuggestionStorage({LocalNamespaceResolver? namespaceResolver})
    : _namespaceResolver = namespaceResolver ?? const LocalNamespaceResolver();

  /// Returns an empty list both when there is genuinely no saved data and
  /// when no local namespace is currently available — consistent with this
  /// method's existing "nothing to show" contract.
  Future<List<AdaptiveHabitSuggestion>> loadSuggestions() async {
    final result = _namespaceResolver.resolveKey(_suggestionsBaseKey);
    if (!result.isAvailable) return [];

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(result.key!);
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

  /// Persists [suggestions]. Throws a [StateError] if no local namespace is
  /// currently available, to avoid silently dropping a save.
  Future<void> saveSuggestions(
    List<AdaptiveHabitSuggestion> suggestions,
  ) async {
    final result = _namespaceResolver.resolveKey(_suggestionsBaseKey);
    if (!result.isAvailable) {
      throw StateError(
        'AdaptiveSuggestionStorage.saveSuggestions: no local namespace available',
      );
    }
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(suggestions.map((s) => s.toJson()).toList());
    await prefs.setString(result.key!, encoded);
  }
}
