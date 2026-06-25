import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/features/progress/domain/ai_weekly_review.dart';
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

  testWidgets('Weekly review opens from the Progress screen', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ProgressScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Weekly review'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'View weekly review'));
    await tester.pumpAndSettle();

    expect(find.text('Recommendation'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Close'));
    await tester.pumpAndSettle();

    expect(find.text('Recommendation'), findsNothing);
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
