import 'package:flutter_test/flutter_test.dart';
import 'package:smart_habit_coach/features/home/data/notification_service.dart';

void main() {
  group('stableNotificationId', () {
    test('returns the same id for the same habit id every time', () {
      final first = stableNotificationId('habit-123');
      final second = stableNotificationId('habit-123');

      expect(first, second);
    });

    test('returns different ids for different habit ids', () {
      final a = stableNotificationId('habit-a');
      final b = stableNotificationId('habit-b');

      expect(a, isNot(b));
    });

    test('always returns a non-negative 32-bit safe integer', () {
      for (final id in ['1', 'abc', '-9999999999999999', '日本語', '']) {
        final result = stableNotificationId(id);
        expect(result, greaterThanOrEqualTo(0));
        expect(result, lessThanOrEqualTo(0x7fffffff));
      }
    });
  });

  group('weekdayNotificationId', () {
    test('returns different ids for different weekdays of the same habit', () {
      final ids = List.generate(
        7,
        (i) => weekdayNotificationId('habit-1', i + 1),
      );
      expect(ids.toSet().length, 7);
    });

    test('returns different ids for different habits on the same weekday', () {
      final a = weekdayNotificationId('habit-a', 1);
      final b = weekdayNotificationId('habit-b', 1);
      expect(a, isNot(b));
    });

    test('all ids fit within the 31-bit signed integer range', () {
      for (final id in ['1', 'habit-xyz', 'long-habit-identifier-99']) {
        for (var w = 1; w <= 7; w++) {
          final result = weekdayNotificationId(id, w);
          expect(result, greaterThanOrEqualTo(0));
          expect(result, lessThanOrEqualTo(0x7fffffff));
        }
      }
    });

    test('ids do not collide with the base stableNotificationId', () {
      const habitId = 'habit-1';
      final base = stableNotificationId(habitId);
      for (var w = 1; w <= 7; w++) {
        expect(weekdayNotificationId(habitId, w), isNot(base));
      }
    });
  });
}
