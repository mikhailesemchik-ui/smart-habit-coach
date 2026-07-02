import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/features/home/domain/date_key.dart';
import 'package:smart_habit_coach/features/progress/domain/ai_weekly_review.dart';
import 'package:smart_habit_coach/features/progress/presentation/day_history_sheet.dart';
import 'package:smart_habit_coach/features/progress/domain/ai_weekly_review_exception.dart';
import 'package:smart_habit_coach/features/progress/domain/ai_weekly_review_source.dart';
import 'package:smart_habit_coach/features/progress/domain/weekly_review.dart';
import 'package:smart_habit_coach/features/progress/presentation/progress_screen.dart';
import 'package:smart_habit_coach/features/progress/presentation/weekly_review_sheet.dart';

class _FailingAiWeeklyReviewSource implements AiWeeklyReviewSource {
  @override
  Future<AiWeeklyReview> generateReview(WeeklyReviewMetrics metrics) async {
    throw const AiWeeklyReviewException('AI review unavailable.');
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // Test 1: tapping a day indicator opens the sheet for that date
  testWidgets('tapping a Last 7 Days indicator opens the sheet for that date', (
    tester,
  ) async {
    // setUp leaves empty prefs → ProgressScreen loads 3 sample habits with no completions
    await tester.pumpWidget(const MaterialApp(home: ProgressScreen()));
    await tester.pumpAndSettle();

    final sixDaysAgo = DateTime.now().subtract(const Duration(days: 6));
    final shortLabel = [
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
      'Sun',
    ][sixDaysAgo.weekday - 1];

    await tester.tap(find.text(shortLabel));
    await tester.pumpAndSettle();

    // Sheet title shows the full formatted date
    expect(find.text(formatSheetDate(sixDaysAgo)), findsOneWidget);
    // 3 sample habits, none completed on that day
    expect(find.text('0 of 3 completed'), findsOneWidget);
  });

  // Test 6: progress metrics refresh after editing a past date
  testWidgets(
    'completion rate refreshes after toggling a habit in the day sheet',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'habits': jsonEncode([
          {
            'id': '1',
            'title': 'Run',
            'scheduledTime': '08:00 AM',
            'iconId': 'fitness',
            'completedDates': [],
          },
        ]),
      });

      await tester.pumpWidget(const MaterialApp(home: ProgressScreen()));
      await tester.pumpAndSettle();
      expect(find.text('0% completion rate'), findsOneWidget);

      // Open yesterday's day sheet
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final label = [
        'Mon',
        'Tue',
        'Wed',
        'Thu',
        'Fri',
        'Sat',
        'Sun',
      ][yesterday.weekday - 1];
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();

      // Mark the habit complete
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();

      // onHabitsChanged has already updated the parent's _habits via setState.
      // The parent is in the element tree (behind the sheet) and reflects the
      // new rate immediately without needing to close the sheet first.
      expect(find.text('0% completion rate'), findsNothing);
      expect(find.text('14% completion rate'), findsOneWidget);
    },
  );

  // Test 7: partial/full/empty day states update correctly
  testWidgets('day sheet subtitle shows partial completion count', (
    tester,
  ) async {
    final today = dateKey(DateTime.now());
    SharedPreferences.setMockInitialValues({
      'habits': jsonEncode([
        {
          'id': '1',
          'title': 'Run',
          'scheduledTime': '08:00 AM',
          'iconId': 'fitness',
          'completedDates': [today],
        },
        {
          'id': '2',
          'title': 'Read',
          'scheduledTime': '09:00 AM',
          'iconId': 'book',
          'completedDates': [],
        },
      ]),
    });

    await tester.pumpWidget(const MaterialApp(home: ProgressScreen()));
    await tester.pumpAndSettle();

    final todayLabel = [
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
      'Sun',
    ][DateTime.now().weekday - 1];
    await tester.tap(find.text(todayLabel));
    await tester.pumpAndSettle();

    expect(find.text('1 of 2 completed'), findsOneWidget);
  });

  testWidgets(
    'Progress reads saved completion dates and shows the correct rate',
    (tester) async {
      final today = todayKey();
      SharedPreferences.setMockInitialValues({
        'habits': jsonEncode([
          {
            'id': '99',
            'title': 'My persisted habit',
            'scheduledTime': '08:00 AM',
            'iconId': 'water',
            'completedDates': [today],
          },
        ]),
      });

      await tester.pumpWidget(const MaterialApp(home: ProgressScreen()));
      await tester.pumpAndSettle();

      // 1 habit, 1 completion out of 7 days → 1/7 ≈ 14%.
      // Would show 0% if sample habits (no completions) were used instead.
      expect(find.text('14% completion rate'), findsOneWidget);
    },
  );

  testWidgets('Weekly review opens from the Progress screen', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ProgressScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Weekly review'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'View weekly review'));
    await tester.pumpAndSettle();

    expect(find.text('Focus for next week'), findsOneWidget);

    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Close'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Close'));
    await tester.pumpAndSettle();

    expect(find.text('Focus for next week'), findsNothing);
  });

  testWidgets(
    'Weekly review sheet does not overflow on a small screen with system nav insets',
    (tester) async {
      addTearDown(tester.view.reset);
      tester.view.physicalSize = const Size(360, 480);
      tester.view.devicePixelRatio = 1.0;
      tester.view.padding = const FakeViewPadding(bottom: 48);

      const localReview = WeeklyReview(
        summary: 'You made some progress this week (45% completed).',
        strongestDay: 'Wednesday',
        weakestDay: 'Sunday',
        recommendation:
            'Try to stay consistent on Sunday to build momentum next week.',
      );
      const metrics = WeeklyReviewMetrics(
        completionRate: 0.45,
        currentStreak: 2,
        bestStreak: 5,
        strongestDay: 'Wednesday',
        weakestDay: 'Sunday',
        completedCount: 9,
        minimumCompletedCount: 0,
        totalPossibleCount: 20,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WeeklyReviewSheet(
              localReview: localReview,
              metrics: metrics,
              service: _FailingAiWeeklyReviewSource(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.widgetWithText(FilledButton, 'Close'), findsOneWidget);
    },
  );
}
