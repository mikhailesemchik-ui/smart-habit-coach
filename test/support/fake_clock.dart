import 'package:smart_habit_coach/core/time/clock.dart';

/// Deterministic [Clock] for tests: always returns [value] until changed.
class FakeClock implements Clock {
  DateTime value;
  FakeClock(this.value);

  @override
  DateTime now() => value;
}
