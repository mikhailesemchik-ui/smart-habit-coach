import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_habit_coach/features/home/domain/date_key.dart';
import 'package:smart_habit_coach/features/home/domain/habit.dart';
import 'package:smart_habit_coach/features/home/presentation/add_habit_sheet.dart';

void main() {
  final today = todayKey();

  // ── Test 11: removing minimumVersion clears today's minimum state ─────────
  testWidgets(
    'saving with blank minimumVersion removes today from minimumCompletedDates',
    (tester) async {
      final initial = Habit(
        id: '1',
        title: 'Yoga',
        scheduledTime: '08:00 AM',
        icon: Icons.fitness_center_outlined,
        minimumVersion: 'Light stretch',
        minimumCompletedDates: {today},
      );

      Habit? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => TextButton(
                onPressed: () async {
                  saved = await showModalBottomSheet<Habit>(
                    context: ctx,
                    isScrollControlled: true,
                    builder: (_) => AddHabitSheet(initialHabit: initial),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Clear the minimum version field.
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Minimum version (optional)'),
        '',
      );
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      expect(saved!.minimumVersion, isNull);
      expect(
        saved!.minimumCompletedDates.contains(today),
        isFalse,
        reason:
            "Today's minimum should be cleared when minimumVersion is removed",
      );
    },
  );

  // ── Test 12: removing minimumVersion preserves past minimum history ────────
  testWidgets(
    'saving with blank minimumVersion preserves past minimumCompletedDates',
    (tester) async {
      const pastDay = '2025-01-15';
      final initial = Habit(
        id: '1',
        title: 'Yoga',
        scheduledTime: '08:00 AM',
        icon: Icons.fitness_center_outlined,
        minimumVersion: 'Light stretch',
        minimumCompletedDates: {pastDay, today},
      );

      Habit? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => TextButton(
                onPressed: () async {
                  saved = await showModalBottomSheet<Habit>(
                    context: ctx,
                    isScrollControlled: true,
                    builder: (_) => AddHabitSheet(initialHabit: initial),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Minimum version (optional)'),
        '',
      );
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      // Past history is retained.
      expect(
        saved!.minimumCompletedDates.contains(pastDay),
        isTrue,
        reason: 'Past minimum history must be preserved',
      );
      // Today is cleared.
      expect(
        saved!.minimumCompletedDates.contains(today),
        isFalse,
        reason: "Today's minimum must be cleared",
      );
    },
  );

  // ── Test 13: removing minimumVersion → habit has no minimumVersion ─────────
  testWidgets('saved habit has null minimumVersion when field is cleared', (
    tester,
  ) async {
    final initial = Habit(
      id: '1',
      title: 'Yoga',
      scheduledTime: '08:00 AM',
      icon: Icons.fitness_center_outlined,
      minimumVersion: 'Light stretch',
    );

    Habit? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () async {
                saved = await showModalBottomSheet<Habit>(
                  context: ctx,
                  isScrollControlled: true,
                  builder: (_) => AddHabitSheet(initialHabit: initial),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Minimum version (optional)'),
      '',
    );
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.minimumVersion, isNull);
    expect(saved!.hasMinimumVersion, isFalse);
  });

  // ── Test 14: re-adding minimumVersion does not erase old history ───────────
  testWidgets(
    're-adding minimumVersion keeps existing minimumCompletedDates intact',
    (tester) async {
      const pastDay = '2025-03-10';
      // Habit with no minimumVersion but historical minimumCompletedDates
      // (e.g. migrated data, or previously had minimum and was later removed).
      final initial = Habit(
        id: '1',
        title: 'Yoga',
        scheduledTime: '08:00 AM',
        icon: Icons.fitness_center_outlined,
        minimumCompletedDates: {pastDay},
      );

      Habit? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => TextButton(
                onPressed: () async {
                  saved = await showModalBottomSheet<Habit>(
                    context: ctx,
                    isScrollControlled: true,
                    builder: (_) => AddHabitSheet(initialHabit: initial),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Add a minimumVersion.
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Minimum version (optional)'),
        'Light stretch',
      );
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      expect(saved!.minimumVersion, 'Light stretch');
      // Old history is preserved when adding minimumVersion.
      expect(
        saved!.minimumCompletedDates.contains(pastDay),
        isTrue,
        reason: 'Existing minimumCompletedDates must not be erased',
      );
    },
  );
}
