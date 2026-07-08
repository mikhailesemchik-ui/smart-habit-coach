import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/storage/local_namespace_resolver.dart';
import '../../../core/time/clock.dart';
import '../domain/adaptive_suggestion.dart';

/// Local persistence for [AdaptiveHabitSuggestion] metadata, mirroring the
/// habit storage pattern. Suggestion records are kept separate from habit
/// JSON so old habit storage stays valid unchanged.
class AdaptiveSuggestionStorage {
  static const _suggestionsBaseKey = 'adaptive_suggestions';

  final LocalNamespaceResolver _namespaceResolver;
  final Clock _clock;

  /// Serializes every write (normal and raw/bulk) issued through this
  /// instance — see `HabitStorage._writeQueue` for the same pattern and
  /// rationale: a load→modify→save mutation must not interleave with
  /// another one on the same instance.
  Future<void> _writeQueue = Future.value();

  AdaptiveSuggestionStorage({
    LocalNamespaceResolver? namespaceResolver,
    Clock? clock,
  }) : _namespaceResolver = namespaceResolver ?? const LocalNamespaceResolver(),
       _clock = clock ?? const SystemClock();

  Future<T> _enqueueWrite<T>(Future<T> Function() action) {
    final result = _writeQueue.then((_) => action());
    _writeQueue = result.then((_) {}, onError: (_) {});
    return result;
  }

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

  /// **Normal mutation path.** Used by all production suggestion state
  /// changes (generation, Apply, Adjust, Keep, and any other status/
  /// evidence update).
  ///
  /// Loads the current namespaced collection, locates [suggestion] by id
  /// (appending it if not found), and stamps `updatedAt` with the injected
  /// [Clock]. Unlike `HabitStorage.upsertHabit`, `createdAt` is **not**
  /// re-derived from any existing stored record: a suggestion's
  /// `createdAt` is an intentional domain timestamp set once by the
  /// detector (the local calendar week it was generated in drives cooldown
  /// and weekly-limit logic), so it is always taken from [suggestion] as
  /// supplied — callers must never construct a suggestion with a changed
  /// `createdAt` for an existing id. `deletedAt` is likewise taken from
  /// [suggestion] as-is.
  ///
  /// Queued behind any other in-flight write on this instance (see
  /// [_enqueueWrite]), so two near-simultaneous calls each see the other's
  /// result rather than racing on a stale load.
  ///
  /// Throws a [StateError] if no local namespace is currently available.
  Future<AdaptiveHabitSuggestion> upsertSuggestion(
    AdaptiveHabitSuggestion suggestion,
  ) {
    return _enqueueWrite(() async {
      final current = await loadSuggestions();
      final index = current.indexWhere((s) => s.id == suggestion.id);
      final stamped = suggestion.copyWith(updatedAt: _clock.now());

      if (index >= 0) {
        current[index] = stamped;
      } else {
        current.add(stamped);
      }

      await _saveSuggestionsUnqueued(current);
      return stamped;
    });
  }

  /// **Raw/bulk persistence path.** Preserves every supplied timestamp
  /// exactly as given — never stamps `updatedAt`. Reserved for migration,
  /// a future cloud-restore path, and tests that need exact timestamps.
  /// Production mutation call sites must use [upsertSuggestion] instead.
  ///
  /// Queued behind any other in-flight write on this instance, same as
  /// [upsertSuggestion].
  ///
  /// Throws a [StateError] if no local namespace is currently available, to
  /// avoid silently dropping a save.
  Future<void> saveSuggestions(List<AdaptiveHabitSuggestion> suggestions) {
    return _enqueueWrite(() => _saveSuggestionsUnqueued(suggestions));
  }

  Future<void> _saveSuggestionsUnqueued(
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
