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
  const aiReview = AiWeeklyReview(
    summary: 'You completed 45% of your habits this week.',
    strongestInsight: 'Wednesday was your most consistent day.',
    weakestInsight: 'Sunday could use more attention next week.',
    recommendation: 'Plan a lighter Sunday routine to keep your streak alive.',
  );

  Future<void> pumpSheet(
    WidgetTester tester,
    AiWeeklyReviewSource service,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WeeklyReviewSheet(
            localReview: localReview,
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
    expect(find.text('Recommendation'), findsNothing);

    delay.complete();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'Displays the AI review on success while keeping the local strongest/weakest day',
    (tester) async {
      final service = _FakeAiWeeklyReviewSource.success(aiReview);
      await pumpSheet(tester, service);
      await tester.pumpAndSettle();

      expect(find.text(aiReview.summary), findsOneWidget);
      expect(find.text('Wednesday'), findsOneWidget);
      expect(find.text(aiReview.strongestInsight), findsOneWidget);
      expect(find.text('Sunday'), findsOneWidget);
      expect(find.text(aiReview.weakestInsight), findsOneWidget);
      expect(find.text(aiReview.recommendation), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Retry'), findsNothing);
    },
  );

  testWidgets(
    'Falls back to the local review with a non-technical notice when the AI request fails',
    (tester) async {
      final service = _FakeAiWeeklyReviewSource.failure(
        const AiWeeklyReviewException('Network unavailable.'),
      );
      await pumpSheet(tester, service);
      await tester.pumpAndSettle();

      expect(find.text(localReview.summary), findsOneWidget);
      expect(find.text(localReview.recommendation), findsOneWidget);
      expect(
        find.textContaining("Showing your local weekly review"),
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

      expect(find.text(localReview.summary), findsOneWidget);
      expect(find.text(localReview.recommendation), findsOneWidget);
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

    expect(find.text(aiReview.summary), findsOneWidget);
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
}
