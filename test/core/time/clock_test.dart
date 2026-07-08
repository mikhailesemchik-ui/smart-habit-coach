import 'package:flutter_test/flutter_test.dart';
import 'package:smart_habit_coach/core/time/clock.dart';

import '../../support/fake_clock.dart';

void main() {
  group('SystemClock', () {
    test('now() returns a UTC timestamp', () {
      final now = const SystemClock().now();
      expect(now.isUtc, isTrue);
    });
  });

  group('FakeClock', () {
    test('returns a stable, injected value regardless of wall-clock time', () {
      final fixed = DateTime.utc(2026, 1, 1);
      final clock = FakeClock(fixed);

      expect(clock.now(), fixed);
      expect(clock.now(), fixed);
    });
  });
}
