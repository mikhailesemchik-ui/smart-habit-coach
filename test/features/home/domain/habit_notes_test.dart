import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_habit_coach/features/home/domain/habit.dart';

void main() {
  final date = DateTime(2026, 6, 27);

  Habit makeHabit() => Habit(
    id: '1',
    title: 'Test',
    scheduledTime: '08:00 AM',
    icon: Icons.check,
  );

  // Test 1
  test('noteFor returns null when completionNotes is empty', () {
    expect(makeHabit().noteFor(date), isNull);
  });

  // Test 2
  test('setNote stores note under the correct date key', () {
    final h = makeHabit().setNote(date, 'Felt great');
    expect(h.noteFor(date), 'Felt great');
  });

  // Test 3
  test('setNote with whitespace-only string removes the entry', () {
    final h = makeHabit().setNote(date, 'hello').setNote(date, '   ');
    expect(h.noteFor(date), isNull);
  });

  // Test 4
  test('setNote with empty string removes the entry', () {
    final h = makeHabit().setNote(date, 'hello').setNote(date, '');
    expect(h.noteFor(date), isNull);
  });

  // Test 5
  test('setNote with null removes the entry', () {
    final h = makeHabit().setNote(date, 'hello').setNote(date, null);
    expect(h.noteFor(date), isNull);
  });

  // Test 6
  test('setNote trims leading and trailing whitespace', () {
    final h = makeHabit().setNote(date, '  Nice  ');
    expect(h.noteFor(date), 'Nice');
  });

  // Test 7
  test('noteFor returns null for a date that has no note', () {
    final h = makeHabit().setNote(date, 'hello');
    expect(h.noteFor(DateTime(2026, 6, 26)), isNull);
  });

  // Test 8
  test('notes survive setCompletionStatus', () {
    final h = makeHabit()
        .setNote(date, 'Good day')
        .setCompletionStatus('2026-06-27', HabitCompletionStatus.full);
    expect(h.noteFor(date), 'Good day');
  });

  // Test 9
  test('notes survive setSkipReason', () {
    final h = makeHabit()
        .setNote(date, 'Tired')
        .setSkipReason(date, HabitSkipReason.tooTired);
    expect(h.noteFor(date), 'Tired');
  });

  // Test 10
  test('notes survive toggleDate', () {
    final h = makeHabit().setNote(date, 'noted').toggleDate('2026-06-27');
    expect(h.noteFor(date), 'noted');
  });

  // Test 11
  test(
    'toJson/fromJson round-trips completionNotes; old JSON loads empty map',
    () {
      final h = makeHabit().setNote(date, 'Round-trip');
      final json = h.toJson();

      final restored = Habit.fromJson(json);
      expect(restored.noteFor(date), 'Round-trip');

      json.remove('completionNotes');
      final legacy = Habit.fromJson(json);
      expect(legacy.noteFor(date), isNull);
    },
  );
}
