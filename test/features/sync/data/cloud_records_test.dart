import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_habit_coach/features/coach/domain/adaptive_suggestion.dart';
import 'package:smart_habit_coach/features/home/domain/habit.dart';
import 'package:smart_habit_coach/features/profile/domain/app_settings.dart';
import 'package:smart_habit_coach/features/sync/data/cloud_records.dart';
import 'package:smart_habit_coach/features/sync/data/cloud_result.dart';

void main() {
  const uid = 'uid-a';
  final createdAt = DateTime.utc(2026, 1, 2, 3);
  final updatedAt = DateTime.utc(2026, 1, 3, 4);
  final deletedAt = DateTime.utc(2026, 1, 4, 5);

  Habit habit({DateTime? deletedAt}) => Habit(
    id: 'habit-1',
    title: 'Walk',
    scheduledTime: '08:00 AM',
    icon: Icons.directions_walk,
    completedDates: {'2026-01-01'},
    minimumCompletedDates: {'2026-01-02'},
    weekdays: const [1, 2, 3, 4, 5],
    status: HabitStatus.paused,
    // 2026-01-07 is a Wednesday, within the habit's Mon–Fri weekdays below —
    // skip reasons on non-scheduled days are intentionally filtered out by
    // Habit.fromJson, so the fixture must stay schedule-consistent.
    skipReasons: const {'2026-01-07': HabitSkipReason.tooTired},
    skipReasonNotes: const {'2026-01-04': 'travel'},
    pausedFromDate: '2026-01-05',
    minimumVersion: 'Walk for 5 minutes',
    trackingType: HabitTrackingType.quantitative,
    targetValue: 10000,
    unit: 'steps',
    quantitativeProgress: const {'2026-01-06': 5200},
    partialReasons: const {'2026-01-06': HabitPartialReason.noTime},
    partialReasonNotes: const {'2026-01-06': 'meeting'},
    completionNotes: const {'2026-01-01': 'felt good'},
    createdAt: createdAt,
    updatedAt: updatedAt,
    deletedAt: deletedAt,
  );

  AdaptiveHabitSuggestion suggestion({DateTime? deletedAt}) =>
      AdaptiveHabitSuggestion(
        id: 'suggestion-1',
        habitId: 'habit-1',
        type: AdaptiveSuggestionType.reduceQuantitativeTarget,
        status: AdaptiveSuggestionStatus.pending,
        createdAt: createdAt,
        analysisStart: DateTime.utc(2026, 1, 1),
        analysisEnd: DateTime.utc(2026, 1, 7),
        evidenceCode: 'partial_progress',
        evidence: const {'partialDays': 3},
        proposedTargetValue: 8000,
        originalTargetValue: 10000,
        originalUnit: 'steps',
        habitTitleSnapshot: 'Walk',
        updatedAt: updatedAt,
        deletedAt: deletedAt,
      );

  test(
    'Habit cloud row round-trips complex history and unknown payload fields',
    () {
      final record = CloudHabitRecord.fromHabit(userId: uid, habit: habit());
      final row = record.toRow(expectedUserId: uid);
      (row['payload'] as Map<String, dynamic>)['futureField'] = 'preserved';

      final parsed = CloudHabitRecord.fromRow(row, expectedUserId: uid);

      expect(parsed.habit.id, 'habit-1');
      expect(parsed.habit.weekdays, const [1, 2, 3, 4, 5]);
      expect(parsed.habit.status, HabitStatus.paused);
      expect(parsed.habit.pausedFromDate, '2026-01-05');
      expect(parsed.habit.completedDates, contains('2026-01-01'));
      expect(parsed.habit.minimumCompletedDates, contains('2026-01-02'));
      expect(parsed.habit.skipReasons['2026-01-07'], HabitSkipReason.tooTired);
      expect(parsed.habit.skipReasonNotes['2026-01-04'], 'travel');
      expect(parsed.habit.minimumVersion, 'Walk for 5 minutes');
      expect(parsed.habit.trackingType, HabitTrackingType.quantitative);
      expect(parsed.habit.targetValue, 10000);
      expect(parsed.habit.unit, 'steps');
      expect(parsed.habit.quantitativeProgress['2026-01-06'], 5200);
      expect(
        parsed.habit.partialReasons['2026-01-06'],
        HabitPartialReason.noTime,
      );
      expect(parsed.habit.partialReasonNotes['2026-01-06'], 'meeting');
      expect(parsed.habit.completionNotes['2026-01-01'], 'felt good');
      expect(parsed.payload['futureField'], 'preserved');
    },
  );

  test('sanity: Habit.fromJson(toJson()) directly preserves the same skip '
      'reason (isolates cloud-mapper bugs from Habit serializer bugs)', () {
    final original = habit();
    final restored = Habit.fromJson(original.toJson());

    expect(restored.skipReasons['2026-01-07'], HabitSkipReason.tooTired);
  });

  test('Habit cloud row preserves tombstone timestamp', () {
    final record = CloudHabitRecord.fromHabit(
      userId: uid,
      habit: habit(deletedAt: deletedAt),
    );

    final parsed = CloudHabitRecord.fromRow(
      record.toRow(expectedUserId: uid),
      expectedUserId: uid,
    );

    expect(parsed.habit.deletedAt, deletedAt);
  });

  test('Malformed habit cloud row is rejected', () {
    expect(
      () => CloudHabitRecord.fromRow({
        'user_id': uid,
        'id': 'habit-1',
        'created_at': createdAt.toIso8601String(),
        'updated_at': 'not-a-date',
        'payload': {'id': 'habit-1'},
      }, expectedUserId: uid),
      throwsA(isA<CloudMappingException>()),
    );
  });

  test(
    'stale payload timestamps cannot override authoritative cloud columns',
    () {
      final record = CloudHabitRecord.fromHabit(userId: uid, habit: habit());
      final row = record.toRow(expectedUserId: uid);
      final payload = row['payload'] as Map<String, dynamic>;
      payload['createdAt'] = DateTime.utc(1999).toIso8601String();
      payload['updatedAt'] = DateTime.utc(1999).toIso8601String();

      final parsed = CloudHabitRecord.fromRow(row, expectedUserId: uid);

      expect(parsed.habit.createdAt, createdAt);
      expect(parsed.habit.updatedAt, updatedAt);
    },
  );

  test(
    'a payload id that disagrees with the authoritative row id is rejected',
    () {
      final record = CloudHabitRecord.fromHabit(userId: uid, habit: habit());
      final row = record.toRow(expectedUserId: uid);
      (row['payload'] as Map<String, dynamic>)['id'] = 'attacker-id';

      expect(
        () => CloudHabitRecord.fromRow(row, expectedUserId: uid),
        throwsA(isA<CloudMappingException>()),
      );
    },
  );

  test('Mismatched habit user id is rejected', () {
    final row = CloudHabitRecord.fromHabit(
      userId: uid,
      habit: habit(),
    ).toRow(expectedUserId: uid);

    expect(
      () => CloudHabitRecord.fromRow(row, expectedUserId: 'uid-b'),
      throwsA(isA<CloudMappingException>()),
    );
  });

  test('Suggestion cloud row round-trips payload and tombstone', () {
    final record = CloudAdaptiveSuggestionRecord.fromSuggestion(
      userId: uid,
      suggestion: suggestion(deletedAt: deletedAt),
    );
    final row = record.toRow(expectedUserId: uid);
    (row['payload'] as Map<String, dynamic>)['futureField'] = 7;

    final parsed = CloudAdaptiveSuggestionRecord.fromRow(
      row,
      expectedUserId: uid,
    );

    expect(parsed.suggestion.id, 'suggestion-1');
    expect(parsed.suggestion.habitId, 'habit-1');
    expect(parsed.suggestion.deletedAt, deletedAt);
    expect(parsed.payload['futureField'], 7);
  });

  test('Settings cloud row round-trips and preserves timestamp', () {
    final settings = AppSettings(
      displayName: 'Jamie',
      themeMode: ThemeMode.dark,
      startOfWeek: StartOfWeek.sunday,
      updatedAt: updatedAt,
    );
    final record = CloudSettingsRecord.fromSettings(
      userId: uid,
      settings: settings,
    );
    final row = record.toRow(expectedUserId: uid);
    (row['payload'] as Map<String, dynamic>)['futureField'] = true;

    final parsed = CloudSettingsRecord.fromRow(row, expectedUserId: uid);

    expect(parsed.settings.displayName, 'Jamie');
    expect(parsed.settings.themeMode, ThemeMode.dark);
    expect(parsed.settings.startOfWeek, StartOfWeek.sunday);
    expect(parsed.settings.updatedAt, updatedAt);
    expect(parsed.payload['futureField'], true);
  });

  test('Settings row rejects invalid required cloud timestamp', () {
    expect(
      () => CloudSettingsRecord.fromRow({
        'user_id': uid,
        'updated_at': 'bad',
        'payload': {'displayName': 'Jamie'},
      }, expectedUserId: uid),
      throwsA(isA<CloudMappingException>()),
    );
  });
}
