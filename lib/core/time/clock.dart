/// Abstraction over "now", so mutation write paths never call
/// `DateTime.now()` directly and can be given a fixed, fake value in tests.
abstract interface class Clock {
  DateTime now();
}

/// Production clock. Always returns UTC, so stored timestamps are
/// unambiguous regardless of device timezone.
class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now().toUtc();
}
