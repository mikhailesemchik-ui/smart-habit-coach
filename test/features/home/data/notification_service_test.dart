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
}
