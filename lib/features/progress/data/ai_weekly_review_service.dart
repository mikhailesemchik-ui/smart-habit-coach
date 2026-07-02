import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../home/domain/habit.dart';

import '../domain/ai_weekly_review.dart';
import '../domain/ai_weekly_review_exception.dart';
import '../domain/ai_weekly_review_response.dart';
import '../domain/ai_weekly_review_source.dart';
import '../domain/weekly_review.dart';

const _requestFailedMessage =
    "Couldn't generate an AI review right now. Please try again.";
const aiWeeklyReviewQuotaMessage =
    "Today's AI review limit has been reached. Showing your local review instead.";

/// Calls the `generate-weekly-review` Supabase Edge Function to turn
/// locally calculated [WeeklyReviewMetrics] into an [AiWeeklyReview].
class AiWeeklyReviewService implements AiWeeklyReviewSource {
  final SupabaseClient _client;

  AiWeeklyReviewService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  @override
  Future<AiWeeklyReview> generateReview(WeeklyReviewMetrics metrics) async {
    final FunctionResponse response;
    try {
      response = await _client.functions
          .invoke(
            'generate-weekly-review',
            body: buildAiWeeklyReviewPayload(metrics),
          )
          .timeout(const Duration(seconds: 20));
    } on FunctionException catch (e) {
      if (isAiWeeklyReviewQuotaExceeded(e.status, e.details)) {
        throw const AiWeeklyReviewException(
          aiWeeklyReviewQuotaMessage,
          isQuotaExceeded: true,
        );
      }
      throw const AiWeeklyReviewException(_requestFailedMessage);
    } catch (_) {
      throw const AiWeeklyReviewException(_requestFailedMessage);
    }

    try {
      return parseAiWeeklyReviewResponse(response.data, metrics: metrics);
    } on AiWeeklyReviewException catch (e) {
      if (kDebugMode) {
        debugPrint(
          'Weekly Review AI response rejected: ${e.diagnosticSummary}',
        );
      }
      rethrow;
    }
  }
}

Map<String, Object?> buildAiWeeklyReviewPayload(WeeklyReviewMetrics metrics) {
  return {
    'completionRate': metrics.completionRate,
    'currentStreak': metrics.currentStreak,
    'bestStreak': metrics.bestStreak,
    'strongestDay': metrics.strongestDay,
    'weakestDay': metrics.weakestDay,
    'completedCount': metrics.completedCount,
    'minimumCompletedCount': metrics.minimumCompletedCount,
    'totalPossibleCount': metrics.totalPossibleCount,
    'skipReasons': _skipReasonPayload(metrics.skipReasonCounts),
    'missedWithoutReason': metrics.missedWithoutReason,
    'partialReasons': _partialReasonPayload(metrics.partialReasonCounts),
    'partialWithoutReason': metrics.partialWithoutReason,
    'habitSummaries': metrics.habitSummaries.map(_habitSummaryPayload).toList(),
    'eligiblePatterns': eligibleWeeklyReviewPatterns(
      metrics,
    ).map(_eligiblePatternPayload).toList(),
    'focusSignals': _focusSignalsPayload(weeklyReviewFocusSignals(metrics)),
  };
}

Map<String, int> _skipReasonPayload(Map<HabitSkipReason, int> counts) {
  return {
    'noTime': counts[HabitSkipReason.noTime] ?? 0,
    'forgot': counts[HabitSkipReason.forgot] ?? 0,
    'tooTired': counts[HabitSkipReason.tooTired] ?? 0,
    'tooDifficult': counts[HabitSkipReason.tooDifficult] ?? 0,
    'other': counts[HabitSkipReason.other] ?? 0,
  };
}

Map<String, int> _partialReasonPayload(Map<HabitPartialReason, int> counts) {
  return {
    'noTime': counts[HabitPartialReason.noTime] ?? 0,
    'tooTired': counts[HabitPartialReason.tooTired] ?? 0,
    'targetTooDifficult': counts[HabitPartialReason.targetTooDifficult] ?? 0,
    'forgotToContinue': counts[HabitPartialReason.forgotToContinue] ?? 0,
    'other': counts[HabitPartialReason.other] ?? 0,
  };
}

Map<String, Object?> _habitSummaryPayload(WeeklyHabitSummary summary) {
  return {
    'habitId': summary.habitId,
    'title': summary.title,
    'trackingType': summary.trackingType.name,
    'scheduledOccurrences': summary.scheduledOccurrences,
    'fullCompletions': summary.fullCompletions,
    'minimumCompletions': summary.minimumCompletions,
    'partialOccurrences': summary.partialOccurrences,
    'missedOccurrences': summary.missedOccurrences,
    'consistencyOccurrences': summary.consistencyOccurrences,
    'completionRate': summary.completionRate,
    'consistencyRate': summary.consistencyRate,
    'currentStreak': summary.currentStreak,
    'bestStreak': summary.bestStreak,
    'targetValue': summary.targetValue,
    'unit': summary.unit,
    'totalLogged': summary.totalLogged,
    'averageProgress': summary.averageProgress,
    'averageLoggedAmount': summary.averageLoggedAmount,
    'skipReasons': _skipReasonPayload(summary.skipReasons),
    'partialReasons': _partialReasonPayload(summary.partialReasons),
    'missedWithoutReason': summary.missedWithoutReason,
    'partialWithoutReason': summary.partialWithoutReason,
  };
}

Map<String, Object?> _eligiblePatternPayload(WeeklyReviewPattern pattern) {
  return {
    'type': pattern.type,
    if (pattern.habitId != null) 'habitId': pattern.habitId,
    if (pattern.habitTitle != null) 'habitTitle': pattern.habitTitle,
    if (pattern.reason != null) 'reason': pattern.reason,
    'count': pattern.count,
  };
}

Map<String, Object?> _focusSignalsPayload(WeeklyReviewFocusSignals signals) {
  return {
    'repeatedForgot': signals.repeatedForgot,
    'repeatedForgotToContinue': signals.repeatedForgotToContinue,
    'repeatedNoTime': signals.repeatedNoTime,
    'repeatedTooTired': signals.repeatedTooTired,
    'repeatedDifficulty': signals.repeatedDifficulty,
    'repeatedPartialProgress': signals.repeatedPartialProgress,
    'repeatedMinimumUse': signals.repeatedMinimumUse,
    'highConsistencyLowFullCompletion':
        signals.highConsistencyLowFullCompletion,
    'strongWeek': signals.strongWeek,
    'noScheduledData': signals.noScheduledData,
    if (signals.primaryHabitTitle != null)
      'primaryHabitTitle': signals.primaryHabitTitle,
  };
}

bool isAiWeeklyReviewQuotaExceeded(int status, Object? data) {
  if (status == 429) return true;
  if (data is! Map) return false;

  final error = data['error'];
  if (error is! Map) return false;

  return error['code'] == 'quota_exceeded';
}
