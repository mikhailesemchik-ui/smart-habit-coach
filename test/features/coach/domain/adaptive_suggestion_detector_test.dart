import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_habit_coach/features/coach/domain/adaptive_suggestion.dart';
import 'package:smart_habit_coach/features/coach/domain/adaptive_suggestion_detector.dart';
import 'package:smart_habit_coach/features/coach/domain/adaptive_suggestion_patterns.dart'
    show median, proposeTarget;
import 'package:smart_habit_coach/features/home/domain/date_key.dart'
    show dateKey, parseDateKey;
import 'package:smart_habit_coach/features/home/domain/habit.dart';

// Thursday. Window analyzed is always [now - 30 days, now - 1 day].
final _now = DateTime(2026, 7, 2);
final _end = DateTime(2026, 7, 1);

/// [count] consecutive local dates ending at [_end] (inclusive), most
/// recent first.
List<DateTime> _lastDays(int count) =>
    List.generate(count, (i) => _end.subtract(Duration(days: i)));

/// [count] dates spread evenly across the last [span] days (ending at
/// [_end]), so evidence dates are not clustered at the very end of the
/// window — the earliest of them must be at least ~14 days back to satisfy
/// the minimum-history rule.
List<DateTime> _spread(int count, {int span = 20}) {
  final days = _lastDays(span);
  if (count <= 1) return [days.last];
  final step = (days.length - 1) / (count - 1);
  return List.generate(count, (i) => days[(i * step).round()]);
}

/// Marks every day in the last 35 days as completed except [exclude].
///
/// Used to give a fixture realistic baseline engagement so tests isolating
/// one specific pattern (e.g. a couple of skip reasons) don't accidentally
/// also read as chronically low engagement and trigger `reduceFrequency`.
Set<String> _fillerCompletions({List<DateTime> exclude = const []}) {
  final excluded = exclude.map(dateKey).toSet();
  return _lastDays(35).map(dateKey).where((k) => !excluded.contains(k)).toSet();
}

Habit _binaryHabit({
  List<int> weekdays = const [1, 2, 3, 4, 5, 6, 7],
  HabitStatus status = HabitStatus.active,
  String? minimumVersion,
  Map<String, HabitSkipReason> skipReasons = const {},
  bool fillEngagement = false,
}) {
  return Habit(
    id: 'h1',
    title: 'Read',
    scheduledTime: '08:00 AM',
    icon: Icons.book,
    weekdays: weekdays,
    status: status,
    minimumVersion: minimumVersion,
    skipReasons: skipReasons,
    completedDates: fillEngagement
        ? _fillerCompletions(
            exclude: skipReasons.keys.map(parseDateKey).toList(),
          )
        : const {},
  );
}

Habit _quantitativeHabit({
  List<int> weekdays = const [1, 2, 3, 4, 5, 6, 7],
  double targetValue = 10,
  Map<String, double> progress = const {},
  Map<String, HabitPartialReason> partialReasons = const {},
  bool fillEngagement = false,
}) {
  return Habit(
    id: 'h2',
    title: 'Water',
    scheduledTime: '08:00 AM',
    icon: Icons.local_drink,
    weekdays: weekdays,
    trackingType: HabitTrackingType.quantitative,
    targetValue: targetValue,
    quantitativeProgress: progress,
    partialReasons: partialReasons,
    // Filler completions don't touch quantitativeProgress, so they never
    // affect median/target-completion evidence — only overall engagement.
    completedDates: fillEngagement
        ? _fillerCompletions(exclude: progress.keys.map(parseDateKey).toList())
        : const {},
  );
}

Map<String, HabitSkipReason> _reasonsOn(
  List<DateTime> dates,
  HabitSkipReason reason,
) => {for (final d in dates) dateKey(d): reason};

Map<String, HabitPartialReason> _partialReasonsOn(
  List<DateTime> dates,
  HabitPartialReason reason,
) => {for (final d in dates) dateKey(d): reason};

Map<String, double> _progressOn(List<DateTime> dates, double value) => {
  for (final d in dates) dateKey(d): value,
};

void main() {
  group('minimum evidence thresholds', () {
    test('less than 14 days of history produces no suggestion', () {
      // All activity within the last 5 days: history is too short even
      // though the occurrence count meets the pattern threshold.
      final habit = _binaryHabit(
        skipReasons: _reasonsOn(
          _lastDays(5).sublist(0, 3),
          HabitSkipReason.tooDifficult,
        ),
      );
      final result = detectAdaptiveSuggestion(
        habits: [habit],
        now: _now,
        previousSuggestions: const [],
      );
      expect(result, isNull);
    });

    test('fewer than 6 expected occurrences produces no suggestion', () {
      // Scheduled only on Mondays: history spans >=14 days but expected
      // occurrences in the 30-day window are well under 6.
      final mondays = _lastDays(
        30,
      ).where((d) => d.weekday == DateTime.monday).toList();
      final habit = _binaryHabit(
        weekdays: const [1],
        skipReasons: _reasonsOn(
          mondays.take(3).toList(),
          HabitSkipReason.tooDifficult,
        ),
      );
      final result = detectAdaptiveSuggestion(
        habits: [habit],
        now: _now,
        previousSuggestions: const [],
      );
      expect(result, isNull);
    });

    test('one or two occurrences of a reason produce no suggestion', () {
      final habit = _binaryHabit(
        skipReasons: _reasonsOn(_spread(2), HabitSkipReason.tooDifficult),
        fillEngagement: true,
      );
      final result = detectAdaptiveSuggestion(
        habits: [habit],
        now: _now,
        previousSuggestions: const [],
      );
      expect(result, isNull);
    });

    test('reasons on dates outside the window are excluded', () {
      // Reasons recorded for "today" and the future never enter the
      // analysis window (which ends the day before `now`).
      final futureDates = [
        _now,
        _now.add(const Duration(days: 1)),
        _now.add(const Duration(days: 2)),
      ];
      final habit = _binaryHabit(
        skipReasons: {
          ..._reasonsOn(futureDates, HabitSkipReason.tooDifficult),
          ..._reasonsOn(_spread(2), HabitSkipReason.tooDifficult),
        },
        fillEngagement: true,
      );
      final result = detectAdaptiveSuggestion(
        habits: [habit],
        now: _now,
        previousSuggestions: const [],
      );
      expect(result, isNull);
    });

    test('unscheduled dates are excluded from evidence', () {
      // Weekdays only Mon-Fri; reasons stored on Saturdays never count.
      final saturdays = _lastDays(
        30,
      ).where((d) => d.weekday == DateTime.saturday).take(3).toList();
      final habit = _binaryHabit(
        weekdays: const [1, 2, 3, 4, 5],
        skipReasons: _reasonsOn(saturdays, HabitSkipReason.tooDifficult),
        fillEngagement: true,
      );
      final result = detectAdaptiveSuggestion(
        habits: [habit],
        now: _now,
        previousSuggestions: const [],
      );
      expect(result, isNull);
    });

    test('paused habits are excluded entirely', () {
      final habit = _binaryHabit(
        status: HabitStatus.paused,
        skipReasons: _reasonsOn(_spread(3), HabitSkipReason.tooDifficult),
      );
      final result = detectAdaptiveSuggestion(
        habits: [habit],
        now: _now,
        previousSuggestions: const [],
      );
      expect(result, isNull);
    });

    test('archived habits are excluded entirely', () {
      final habit = _binaryHabit(
        status: HabitStatus.archived,
        skipReasons: _reasonsOn(_spread(3), HabitSkipReason.tooDifficult),
      );
      final result = detectAdaptiveSuggestion(
        habits: [habit],
        now: _now,
        previousSuggestions: const [],
      );
      expect(result, isNull);
    });

    test('the current incomplete day never contributes evidence', () {
      final dates = [..._spread(2), _now];
      final habit = _binaryHabit(
        skipReasons: _reasonsOn(dates, HabitSkipReason.tooDifficult),
        fillEngagement: true,
      );
      final result = detectAdaptiveSuggestion(
        habits: [habit],
        now: _now,
        previousSuggestions: const [],
      );
      // Only 2 of the 3 dates fall inside the window, below the threshold.
      expect(result, isNull);
    });
  });

  group('too difficult pattern', () {
    test('repeated tooDifficult suggests adding a minimum version', () {
      final habit = _binaryHabit(
        skipReasons: _reasonsOn(_spread(3), HabitSkipReason.tooDifficult),
      );
      final result = detectAdaptiveSuggestion(
        habits: [habit],
        now: _now,
        previousSuggestions: const [],
      );
      expect(result, isNotNull);
      expect(result!.type, AdaptiveSuggestionType.addMinimumVersion);
      expect(result.evidenceCode, 'repeated_too_difficult');
    });

    test('an existing minimum version prevents that recommendation', () {
      final habit = _binaryHabit(
        minimumVersion: 'Read 1 page',
        skipReasons: _reasonsOn(_spread(3), HabitSkipReason.tooDifficult),
        fillEngagement: true,
      );
      final result = detectAdaptiveSuggestion(
        habits: [habit],
        now: _now,
        previousSuggestions: const [],
      );
      expect(result, isNull);
    });
  });

  group('quantitative target pattern', () {
    test('repeated targetTooDifficult suggests a target reduction', () {
      final habit = _quantitativeHabit(
        targetValue: 10,
        progress: _progressOn(_spread(10, span: 25), 5),
        partialReasons: _partialReasonsOn(
          _spread(3, span: 25),
          HabitPartialReason.targetTooDifficult,
        ),
      );
      final result = detectAdaptiveSuggestion(
        habits: [habit],
        now: _now,
        previousSuggestions: const [],
      );
      expect(result, isNotNull);
      expect(result!.type, AdaptiveSuggestionType.reduceQuantitativeTarget);
      expect(result.evidenceCode, 'repeated_target_too_difficult_reason');
      expect(result.proposedTargetValue, 5.0);
    });

    test('repeated partial progress alone may suggest a target reduction', () {
      final habit = _quantitativeHabit(
        targetValue: 10,
        // 13 of 30 expected occurrences (>=40%) without an explicit reason.
        progress: _progressOn(_spread(13, span: 25), 4),
      );
      final result = detectAdaptiveSuggestion(
        habits: [habit],
        now: _now,
        previousSuggestions: const [],
      );
      expect(result, isNotNull);
      expect(result!.evidenceCode, 'quantitative_consistency_gap');
    });

    test('strong target completion prevents a target reduction', () {
      final habit = _quantitativeHabit(
        targetValue: 10,
        // Reaching the full target on 10 of 30 occurrences (>=30%) blocks
        // the suggestion even with an explicit difficulty reason present.
        progress: _progressOn(_spread(10, span: 25), 10),
        partialReasons: _partialReasonsOn(
          _spread(3, span: 25),
          HabitPartialReason.targetTooDifficult,
        ),
        fillEngagement: true,
      );
      final result = detectAdaptiveSuggestion(
        habits: [habit],
        now: _now,
        previousSuggestions: const [],
      );
      expect(result, isNull);
    });

    test('raw median calculation is correct for odd and even counts', () {
      // Pure helper, no clamping: verifies the median itself independent of
      // any target's 50% floor.
      expect(median([2, 4, 6]), 4.0);
      expect(median([2, 4, 6, 8]), 5.0);
      expect(median([]), isNull);
    });

    test('final proposal never exceeds the current target', () {
      final habit = _quantitativeHabit(targetValue: 10);
      // Raw median (12.5) is above the current target, so it is capped.
      final proposed = proposeTarget(habit, [12, 13, 11, 14]);
      expect(proposed, 10.0);
    });

    test('final proposal respects the 50% floor', () {
      final habit = _quantitativeHabit(targetValue: 10);
      // Raw median (1) is far below 50% of the target (5), so it is
      // floored rather than proposed as-is.
      final proposed = proposeTarget(habit, [1, 1, 1]);
      expect(proposed, 5.0);
    });

    test('final proposal equals the raw median when within [50%, 100%]', () {
      // target=8: 50% floor is 4, raw median of [2,4,6] is 4 → no clamping.
      final habit8 = _quantitativeHabit(targetValue: 8);
      expect(proposeTarget(habit8, [2, 4, 6]), 4.0);
      // target=10: 50% floor is 5, raw median of [2,4,6,8] is 5 → no clamping.
      final habit10 = _quantitativeHabit(targetValue: 10);
      expect(proposeTarget(habit10, [2, 4, 6, 8]), 5.0);
    });
  });

  group('no time pattern', () {
    test('repeated noTime with no minimum version suggests adding one', () {
      final habit = _binaryHabit(
        skipReasons: _reasonsOn(_spread(3), HabitSkipReason.noTime),
      );
      final result = detectAdaptiveSuggestion(
        habits: [habit],
        now: _now,
        previousSuggestions: const [],
      );
      expect(result, isNotNull);
      expect(result!.type, AdaptiveSuggestionType.addMinimumVersion);
      expect(result.evidenceCode, 'repeated_no_time');
    });

    test(
      'repeated noTime with a minimum version suggests reviewing schedule',
      () {
        final habit = _binaryHabit(
          minimumVersion: 'Read 1 page',
          skipReasons: _reasonsOn(_spread(3), HabitSkipReason.noTime),
        );
        final result = detectAdaptiveSuggestion(
          habits: [habit],
          now: _now,
          previousSuggestions: const [],
        );
        expect(result, isNotNull);
        expect(result!.type, AdaptiveSuggestionType.reviewSchedule);
      },
    );
  });

  group('too tired pattern', () {
    test(
      'repeated tooTired suggests changing schedule without inventing a time',
      () {
        final habit = _binaryHabit(
          skipReasons: _reasonsOn(_spread(3), HabitSkipReason.tooTired),
        );
        final result = detectAdaptiveSuggestion(
          habits: [habit],
          now: _now,
          previousSuggestions: const [],
        );
        expect(result, isNotNull);
        expect(result!.type, AdaptiveSuggestionType.changeScheduledTime);
        expect(result.proposedTime, isNull);
      },
    );
  });

  group('forgetting pattern', () {
    test('repeated forgetting produces no suggestion in Phase 1', () {
      final habit = _binaryHabit(
        skipReasons: _reasonsOn(_spread(5), HabitSkipReason.forgot),
        fillEngagement: true,
      );
      final result = detectAdaptiveSuggestion(
        habits: [habit],
        now: _now,
        previousSuggestions: const [],
      );
      expect(result, isNull);
    });
  });

  group('frequency mismatch pattern', () {
    Habit lowEngagementHabit() {
      // Daily habit (>3x/week) with low engagement in the 3 most recent
      // full Mon-Sun weeks before `_end`.
      final completed = <String>{};
      for (var i = 0; i < 30; i++) {
        final day = _end.subtract(Duration(days: i));
        // Complete only every 4th day → engagement well under 50%.
        if (i % 4 == 0) completed.add(dateKey(day));
      }
      return Habit(
        id: 'h1',
        title: 'Read',
        scheduledTime: '08:00 AM',
        icon: Icons.book,
        weekdays: const [1, 2, 3, 4, 5, 6, 7],
        completedDates: completed,
      );
    }

    test('frequency mismatch requires at least 3 low-engagement weeks', () {
      final habit = lowEngagementHabit();
      final result = detectAdaptiveSuggestion(
        habits: [habit],
        now: _now,
        previousSuggestions: const [],
      );
      expect(result, isNotNull);
      expect(result!.type, AdaptiveSuggestionType.reduceFrequency);
    });

    test(
      'scheduled 3 times per week or fewer is exempt from frequency mismatch',
      () {
        final completed = <String>{};
        final habit = Habit(
          id: 'h1',
          title: 'Read',
          scheduledTime: '08:00 AM',
          icon: Icons.book,
          weekdays: const [1, 3, 5],
          completedDates: completed,
        );
        final result = detectAdaptiveSuggestion(
          habits: [habit],
          now: _now,
          previousSuggestions: const [],
        );
        expect(result, isNull);
      },
    );
  });

  group('candidate ranking', () {
    test('only one candidate is returned even with multiple matches', () {
      final habitA = _binaryHabit(
        skipReasons: _reasonsOn(_spread(3), HabitSkipReason.tooDifficult),
      );
      final habitB = _quantitativeHabit(
        progress: _progressOn(_spread(13, span: 25), 4),
      );
      final result = detectAdaptiveSuggestion(
        habits: [habitA, habitB],
        now: _now,
        previousSuggestions: const [],
      );
      // Explicit-reason addMinimumVersion (rank 1) outranks the ratio-based
      // quantitative gap (rank 4).
      expect(result, isNotNull);
      expect(result!.habitId, habitA.id);
    });

    test('ranking is deterministic regardless of input order', () {
      final habitA = _binaryHabit(
        skipReasons: _reasonsOn(_spread(3), HabitSkipReason.tooDifficult),
      );
      final habitB = _quantitativeHabit(
        progress: _progressOn(_spread(13, span: 25), 4),
      );
      final r1 = detectAdaptiveSuggestion(
        habits: [habitA, habitB],
        now: _now,
        previousSuggestions: const [],
      );
      final r2 = detectAdaptiveSuggestion(
        habits: [habitB, habitA],
        now: _now,
        previousSuggestions: const [],
      );
      expect(r1?.habitId, r2?.habitId);
      expect(r1?.type, r2?.type);
    });
  });

  group('weekly limit', () {
    test(
      'no suggestion is generated when one was already created this week',
      () {
        final habit = _binaryHabit(
          skipReasons: _reasonsOn(_spread(3), HabitSkipReason.tooDifficult),
        );
        final previous = AdaptiveHabitSuggestion(
          id: 'prev-1',
          habitId: 'other-habit',
          type: AdaptiveSuggestionType.reviewSchedule,
          createdAt: _now.subtract(const Duration(days: 1)),
          analysisStart: _now.subtract(const Duration(days: 31)),
          analysisEnd: _now.subtract(const Duration(days: 2)),
          evidenceCode: 'x',
        );
        final result = detectAdaptiveSuggestion(
          habits: [habit],
          now: _now,
          previousSuggestions: [previous],
        );
        expect(result, isNull);
      },
    );
  });

  group('rejection/keep cooldown', () {
    AdaptiveHabitSuggestion previousFor({
      required DateTime createdAt,
      required AdaptiveSuggestionStatus status,
    }) => AdaptiveHabitSuggestion(
      id: 'prev-1',
      habitId: 'h1',
      type: AdaptiveSuggestionType.addMinimumVersion,
      status: status,
      createdAt: createdAt,
      analysisStart: createdAt.subtract(const Duration(days: 30)),
      analysisEnd: createdAt.subtract(const Duration(days: 1)),
      evidenceCode: 'repeated_too_difficult',
    );

    test('a rejected suggestion is not repeated within 28 days', () {
      final habit = _binaryHabit(
        skipReasons: _reasonsOn(_spread(3), HabitSkipReason.tooDifficult),
        fillEngagement: true,
      );
      final previous = previousFor(
        createdAt: _now.subtract(const Duration(days: 10)),
        status: AdaptiveSuggestionStatus.rejected,
      );
      final result = detectAdaptiveSuggestion(
        habits: [habit],
        now: _now,
        previousSuggestions: [previous],
      );
      expect(result, isNull);
    });

    test('a kept suggestion is not repeated within 28 days', () {
      final habit = _binaryHabit(
        skipReasons: _reasonsOn(_spread(3), HabitSkipReason.tooDifficult),
        fillEngagement: true,
      );
      final previous = previousFor(
        createdAt: _now.subtract(const Duration(days: 10)),
        status: AdaptiveSuggestionStatus.kept,
      );
      final result = detectAdaptiveSuggestion(
        habits: [habit],
        now: _now,
        previousSuggestions: [previous],
      );
      expect(result, isNull);
    });

    test('the same suggestion type may be re-evaluated after 28 days', () {
      final habit = _binaryHabit(
        skipReasons: _reasonsOn(_spread(3), HabitSkipReason.tooDifficult),
      );
      final previous = previousFor(
        createdAt: _now.subtract(const Duration(days: 40)),
        status: AdaptiveSuggestionStatus.rejected,
      );
      final result = detectAdaptiveSuggestion(
        habits: [habit],
        now: _now,
        previousSuggestions: [previous],
      );
      expect(result, isNotNull);
    });

    test('applied reconsideration is blocked when evidence is not newer', () {
      final habit = _binaryHabit(
        skipReasons: _reasonsOn(_spread(3), HabitSkipReason.tooDifficult),
        fillEngagement: true,
      );
      // Applied 40 days ago (past the 28-day cooldown), but its analysis
      // window already covers up to the same day the new candidate's
      // window would end on — no newer evidence has accumulated since.
      final previous = AdaptiveHabitSuggestion(
        id: 'prev-1',
        habitId: 'h1',
        type: AdaptiveSuggestionType.addMinimumVersion,
        status: AdaptiveSuggestionStatus.applied,
        createdAt: _now.subtract(const Duration(days: 40)),
        analysisStart: _now.subtract(const Duration(days: 70)),
        analysisEnd: _end,
        evidenceCode: 'repeated_too_difficult',
      );
      final result = detectAdaptiveSuggestion(
        habits: [habit],
        now: _now,
        previousSuggestions: [previous],
      );
      expect(result, isNull);
    });

    test('applied reconsideration proceeds once evidence is newer', () {
      final habit = _binaryHabit(
        skipReasons: _reasonsOn(_spread(3), HabitSkipReason.tooDifficult),
        fillEngagement: true,
      );
      final previous = AdaptiveHabitSuggestion(
        id: 'prev-1',
        habitId: 'h1',
        type: AdaptiveSuggestionType.addMinimumVersion,
        status: AdaptiveSuggestionStatus.applied,
        createdAt: _now.subtract(const Duration(days: 40)),
        analysisStart: _now.subtract(const Duration(days: 70)),
        analysisEnd: _now.subtract(const Duration(days: 41)),
        evidenceCode: 'repeated_too_difficult',
      );
      final result = detectAdaptiveSuggestion(
        habits: [habit],
        now: _now,
        previousSuggestions: [previous],
      );
      expect(result, isNotNull);
    });
  });

  group('serialization', () {
    test('round-trips through JSON', () {
      final suggestion = AdaptiveHabitSuggestion(
        id: 'h1-addMinimumVersion-2026-07-02',
        habitId: 'h1',
        type: AdaptiveSuggestionType.addMinimumVersion,
        status: AdaptiveSuggestionStatus.pending,
        createdAt: _now,
        analysisStart: _now.subtract(const Duration(days: 30)),
        analysisEnd: _end,
        evidenceCode: 'repeated_too_difficult',
        evidence: const {'tooDifficultCount': 3},
      );
      final restored = AdaptiveHabitSuggestion.fromJson(suggestion.toJson());
      expect(restored, isNotNull);
      expect(restored!.id, suggestion.id);
      expect(restored.type, suggestion.type);
      expect(restored.evidence, suggestion.evidence);
    });

    test('malformed suggestion JSON is ignored, not thrown', () {
      expect(AdaptiveHabitSuggestion.fromJson({'id': 'x'}), isNull);
      expect(AdaptiveHabitSuggestion.fromJson(const {}), isNull);
    });

    test('old-shaped JSON without optional fields still loads', () {
      final json = {
        'id': 'h1-addMinimumVersion-2026-07-02',
        'habitId': 'h1',
        'type': 'addMinimumVersion',
        'status': 'pending',
        'createdAt': _now.toIso8601String(),
        'analysisStart': _now.toIso8601String(),
        'analysisEnd': _now.toIso8601String(),
        'evidenceCode': 'repeated_too_difficult',
      };
      final restored = AdaptiveHabitSuggestion.fromJson(json);
      expect(restored, isNotNull);
      expect(restored!.evidence, isEmpty);
      expect(restored.proposedTargetValue, isNull);
    });

    test('evidence never contains free-text note fields', () {
      final habit = _binaryHabit(
        skipReasons: _reasonsOn(_spread(3), HabitSkipReason.tooDifficult),
      );
      final result = detectAdaptiveSuggestion(
        habits: [habit],
        now: _now,
        previousSuggestions: const [],
      );
      expect(result, isNotNull);
      for (final value in result!.evidence.values) {
        expect(value, isA<num>());
      }
      final json = result.toJson();
      expect(json.containsKey('note'), isFalse);
      expect(json.containsKey('noteText'), isFalse);
    });
  });
}
