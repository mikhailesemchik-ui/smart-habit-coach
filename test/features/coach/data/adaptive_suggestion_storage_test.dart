import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/core/storage/local_namespace_resolver.dart';
import 'package:smart_habit_coach/features/coach/data/adaptive_suggestion_storage.dart';
import 'package:smart_habit_coach/features/coach/domain/adaptive_suggestion.dart';

import '../../../support/test_namespace.dart';

AdaptiveHabitSuggestion _suggestion(String id) {
  return AdaptiveHabitSuggestion(
    id: id,
    habitId: 'h1',
    type: AdaptiveSuggestionType.addMinimumVersion,
    createdAt: DateTime.utc(2026, 1, 1),
    analysisStart: DateTime.utc(2025, 12, 1),
    analysisEnd: DateTime.utc(2025, 12, 31),
    evidenceCode: 'code',
  );
}

void main() {
  tearDown(() {
    LocalNamespaceResolver.debugUidOverride = testNamespaceUid;
  });

  group('AdaptiveSuggestionStorage', () {
    test('loadSuggestions returns [] when nothing has been saved', () async {
      SharedPreferences.setMockInitialValues({});

      final result = await AdaptiveSuggestionStorage().loadSuggestions();

      expect(result, isEmpty);
    });

    test('saveSuggestions then loadSuggestions round-trips', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = AdaptiveSuggestionStorage();

      await storage.saveSuggestions([_suggestion('s1')]);
      final loaded = await storage.loadSuggestions();

      expect(loaded.single.id, 's1');
    });
  });

  group('AdaptiveSuggestionStorage namespacing', () {
    test('saves and loads under a namespaced key when a UID is set', () async {
      SharedPreferences.setMockInitialValues({});
      LocalNamespaceResolver.debugUidOverride = 'uid-a';
      final storage = AdaptiveSuggestionStorage();

      await storage.saveSuggestions([_suggestion('s1')]);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('adaptive_suggestions:uid-a'), isTrue);
      expect(prefs.containsKey('adaptive_suggestions'), isFalse);
    });

    test('two different UIDs read/write fully isolated data', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = AdaptiveSuggestionStorage();

      LocalNamespaceResolver.debugUidOverride = 'uid-a';
      await storage.saveSuggestions([_suggestion('a')]);

      LocalNamespaceResolver.debugUidOverride = 'uid-b';
      await storage.saveSuggestions([_suggestion('b')]);
      final bLoaded = await storage.loadSuggestions();

      LocalNamespaceResolver.debugUidOverride = 'uid-a';
      final aLoaded = await storage.loadSuggestions();

      expect(aLoaded.single.id, 'a');
      expect(bLoaded.single.id, 'b');
    });

    test('loadSuggestions returns [] when no UID is available', () async {
      SharedPreferences.setMockInitialValues({});
      LocalNamespaceResolver.debugUidOverride = null;

      final result = await AdaptiveSuggestionStorage().loadSuggestions();

      expect(result, isEmpty);
    });

    test('saveSuggestions throws when no UID is available', () async {
      SharedPreferences.setMockInitialValues({});
      LocalNamespaceResolver.debugUidOverride = null;

      expect(
        () => AdaptiveSuggestionStorage().saveSuggestions([_suggestion('s1')]),
        throwsStateError,
      );
    });
  });
}
