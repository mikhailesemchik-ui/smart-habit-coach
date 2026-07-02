import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_habit_coach/features/progress/data/ai_weekly_review_service.dart';
import 'package:smart_habit_coach/features/progress/domain/ai_weekly_review.dart';
import 'package:smart_habit_coach/features/progress/domain/ai_weekly_review_exception.dart';
import 'package:smart_habit_coach/features/progress/domain/ai_weekly_review_source.dart';
import 'package:smart_habit_coach/features/progress/domain/weekly_review.dart';
import 'package:smart_habit_coach/features/progress/presentation/weekly_review_sheet.dart';

class _FakeAiWeeklyReviewSource implements AiWeeklyReviewSource {
  final AiWeeklyReview? review;
  final AiWeeklyReviewException? error;
  final Completer<void>? delay;
  var callCount = 0;

  _FakeAiWeeklyReviewSource.success(this.review) : error = null, delay = null;

  _FakeAiWeeklyReviewSource.failure(this.error) : review = null, delay = null;

  _FakeAiWeeklyReviewSource.pending(this.delay, this.review) : error = null;

  @override
  Future<AiWeeklyReview> generateReview(WeeklyReviewMetrics metrics) async {
    callCount++;
    if (delay != null) await delay!.future;
    if (error != null) throw error!;
    return review!;
  }
}

class _DelayedAfterFirstCallSource implements AiWeeklyReviewSource {
  final Completer<void> secondCallDelay;
  var callCount = 0;

  _DelayedAfterFirstCallSource(this.secondCallDelay);

  @override
  Future<AiWeeklyReview> generateReview(WeeklyReviewMetrics metrics) async {
    callCount++;
    if (callCount > 1) {
      await secondCallDelay.future;
    }
    throw const AiWeeklyReviewException('Network unavailable.');
  }
}

class _RetryingFakeSource implements AiWeeklyReviewSource {
  final AiWeeklyReview review;
  final bool Function() attempt;

  _RetryingFakeSource({required this.review, required this.attempt});

  @override
  Future<AiWeeklyReview> generateReview(WeeklyReviewMetrics metrics) async {
    if (attempt()) {
      throw const AiWeeklyReviewException('Temporary failure.');
    }
    return review;
  }
}

void main() {
  const localReview = WeeklyReview(
    summary: 'You completed 9 of 20 scheduled habits.',
    strongestDay: 'Wednesday',
    weakestDay: 'Sunday',
    recommendation:
        'Pick one scheduled habit and plan one specific time for it next week.',
    whatWentWell: [
      'You completed 9 of 20 scheduled habits.',
      'Your strongest habit this week was Reading.',
    ],
    partialProgress: ['You used the minimum version of Reading on 2 days.'],
    patterns: ['No repeated patterns were recorded this week.'],
    focusNextWeek:
        'Pick one scheduled habit and plan one specific time for it next week.',
  );
  const metrics = WeeklyReviewMetrics(
    completionRate: 0.45,
    currentStreak: 2,
    bestStreak: 5,
    strongestDay: 'Wednesday',
    weakestDay: 'Sunday',
    completedCount: 9,
    minimumCompletedCount: 2,
    totalPossibleCount: 20,
  );
  const aiReview = AiWeeklyReview(
    summary: 'You completed reading on 5 of 7 scheduled days.',
    recommendation: 'Choose one protected 20-minute reading slot.',
    whatWentWell: ['You completed reading on 5 of 7 scheduled days.'],
    partialProgress: ['You used the minimum version twice.'],
    patterns: ['Limited time was recorded on 3 days.'],
    focusNextWeek: 'Choose one protected 20-minute reading slot.',
  );

  Future<void> pumpSheet(
    WidgetTester tester,
    AiWeeklyReviewSource service, {
    WeeklyReview review = localReview,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WeeklyReviewSheet(
            localReview: review,
            metrics: metrics,
            service: service,
          ),
        ),
      ),
    );
  }

  testWidgets('Shows a loading indicator while requesting the AI review', (
    tester,
  ) async {
    final delay = Completer<void>();
    final service = _FakeAiWeeklyReviewSource.pending(delay, aiReview);
    await pumpSheet(tester, service);
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Focus for next week'), findsNothing);

    delay.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('Displays the AI review using all four sections', (tester) async {
    final service = _FakeAiWeeklyReviewSource.success(aiReview);
    await pumpSheet(tester, service);
    await tester.pumpAndSettle();

    expect(find.text('Weekly Review'), findsOneWidget);
    expect(find.text('What went well'), findsOneWidget);
    expect(find.text('Partial progress'), findsOneWidget);
    expect(find.text('Patterns noticed'), findsOneWidget);
    expect(find.text('Focus for next week'), findsOneWidget);
    expect(find.text(aiReview.whatWentWell.single), findsOneWidget);
    expect(find.text(aiReview.partialProgress.single), findsOneWidget);
    expect(find.text(aiReview.patterns.single), findsOneWidget);
    expect(find.text(aiReview.focusNextWeek), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Retry'), findsNothing);
  });

  testWidgets(
    'Falls back to the local review with a non-technical notice when the AI request fails',
    (tester) async {
      final service = _FakeAiWeeklyReviewSource.failure(
        const AiWeeklyReviewException('Network unavailable.'),
      );
      await pumpSheet(tester, service);
      await tester.pumpAndSettle();

      expect(find.text(localReview.whatWentWell.first), findsOneWidget);
      expect(find.text(localReview.partialProgress.first), findsOneWidget);
      expect(find.text(localReview.patterns.first), findsOneWidget);
      expect(find.text(localReview.focusNextWeek), findsOneWidget);
      expect(
        find.textContaining('Showing your local weekly review'),
        findsOneWidget,
      );
      expect(find.text('Network unavailable.'), findsNothing);
      expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Close'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Falls back to the local review with the quota notice when the daily limit is reached',
    (tester) async {
      final service = _FakeAiWeeklyReviewSource.failure(
        const AiWeeklyReviewException(
          aiWeeklyReviewQuotaMessage,
          isQuotaExceeded: true,
        ),
      );
      await pumpSheet(tester, service);
      await tester.pumpAndSettle();

      expect(find.text(localReview.whatWentWell.first), findsOneWidget);
      expect(find.text(localReview.focusNextWeek), findsOneWidget);
      expect(find.text(aiWeeklyReviewQuotaMessage), findsOneWidget);
      expect(find.textContaining('Network unavailable'), findsNothing);
      expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Retry after a failure can succeed', (tester) async {
    var attempt = 0;
    final service = _RetryingFakeSource(
      review: aiReview,
      attempt: () {
        attempt++;
        return attempt == 1;
      },
    );
    await pumpSheet(tester, service);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Retry'));
    await tester.pumpAndSettle();

    expect(find.text(aiReview.whatWentWell.single), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Retry'), findsNothing);
  });

  testWidgets('Tapping Retry twice in a row only sends one extra request', (
    tester,
  ) async {
    final secondCallDelay = Completer<void>();
    final service = _DelayedAfterFirstCallSource(secondCallDelay);
    await pumpSheet(tester, service);
    await tester.pumpAndSettle();

    expect(service.callCount, 1);

    await tester.tap(find.widgetWithText(TextButton, 'Retry'));
    await tester.tap(find.widgetWithText(TextButton, 'Retry'));
    await tester.pump();

    expect(service.callCount, 2);

    secondCallDelay.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('Renders long section text without overflow on a compact screen', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(360, 480);
    tester.view.devicePixelRatio = 1.0;

    const longReview = WeeklyReview(
      summary: 'A long local summary.',
      strongestDay: null,
      weakestDay: null,
      recommendation:
          'Choose one specific time for the habit that needs the most attention next week.',
      whatWentWell: [
        'You completed a scheduled habit with a deliberately long title that should wrap safely inside the weekly review sheet.',
      ],
      partialProgress: [
        'You made partial progress on a quantitative habit with a long unit label and the text should wrap without layout overflow.',
      ],
      patterns: [
        'No repeated patterns were recorded this week, even with a long explanatory sentence that needs wrapping.',
      ],
      focusNextWeek:
          'Choose one specific time for the habit that needs the most attention next week.',
    );
    final service = _FakeAiWeeklyReviewSource.failure(
      const AiWeeklyReviewException('Network unavailable.'),
    );

    await pumpSheet(tester, service, review: longReview);
    await tester.pumpAndSettle();

    expect(find.text('What went well'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
