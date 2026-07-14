import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../domain/habit.dart';
import '../domain/scheduled_time.dart';

/// Generates a stable, deterministic notification ID from a habit ID.
/// Must not rely on [String.hashCode], which is not guaranteed to be
/// stable across platforms or app runs.
int stableNotificationId(String habitId) {
  var hash = 0;
  for (final codeUnit in habitId.codeUnits) {
    hash = (hash * 31 + codeUnit) & 0x7fffffff;
  }
  return hash;
}

/// Generates a per-weekday notification ID that is stable, unique within
/// the 31-bit signed integer space, and collision-safe across habits.
///
/// Formula: (stableId & 0x0FFFFFFF) << 3 | (weekday - 1)
/// Max value: (268_435_455 << 3) | 6 = 2_147_483_646 (fits in 31 bits).
int weekdayNotificationId(String habitId, int weekday) {
  return (stableNotificationId(habitId) & 0x0FFFFFFF) << 3 | (weekday - 1);
}

/// Notification permission state, abstracted away from the underlying
/// plugin/platform. [unknown] covers platforms where status cannot be
/// reliably queried (e.g. web) rather than guessing granted or denied.
enum NotificationPermissionStatus { granted, denied, unknown }

/// Schedules and cancels weekday-aware local reminders for habits.
/// This wraps `flutter_local_notifications` so it can be swapped or faked
/// independently of the UI.
class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// Suppresses this class's `debugPrint` diagnostics. Set once for the
  /// whole suite in `test/flutter_test_config.dart` — widget tests
  /// routinely construct a real `NotificationService()` with no platform
  /// channel handler registered, so every plugin call fails and is caught
  /// here by design; that's expected noise in tests, not a real error, and
  /// production behavior (the try/catch itself) is unchanged either way.
  @visibleForTesting
  static bool debugSuppressLogging = false;

  void _logFailure(String context, Object error) {
    if (debugSuppressLogging) return;
    debugPrint('NotificationService.$context failed: $error');
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        ),
      );
      await _plugin.initialize(settings: settings);
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } catch (error) {
      _logFailure('initialize', error);
    }
  }

  /// Replaces all existing reminders for [habit] with weekday-specific ones.
  /// Calls [cancelHabitReminder] first to clear stale schedules (including
  /// old daily-only IDs from before weekday scheduling was introduced).
  Future<void> scheduleHabitReminder(Habit habit) async {
    final time = parseScheduledTime(habit.scheduledTime);
    if (time == null) return;

    await cancelHabitReminder(habit.id);

    for (final weekday in habit.weekdays) {
      try {
        await _plugin.zonedSchedule(
          id: weekdayNotificationId(habit.id, weekday),
          title: habit.title,
          body: 'Time to complete your habit',
          scheduledDate: _nextInstanceOf(time, weekday),
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'habit_reminders',
              'Habit reminders',
            ),
            iOS: DarwinNotificationDetails(),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        );
      } catch (error) {
        _logFailure('scheduleHabitReminder', error);
      }
    }
  }

  /// Cancels all reminders for [habitId]: the legacy base ID and all seven
  /// weekday-specific IDs. This ensures a clean slate when rescheduling.
  Future<void> cancelHabitReminder(String habitId) async {
    try {
      await _plugin.cancel(id: stableNotificationId(habitId));
    } catch (error) {
      _logFailure('cancelHabitReminder', error);
    }
    for (var w = 1; w <= 7; w++) {
      try {
        await _plugin.cancel(id: weekdayNotificationId(habitId, w));
      } catch (error) {
        _logFailure('cancelHabitReminder', error);
      }
    }
  }

  /// Cancels every currently-scheduled reminder, regardless of habit.
  /// Used by reconciliation (e.g. after an account/UID switch) to clear out
  /// reminders that may belong to a previously-active identity before
  /// rescheduling only the current identity's active habits.
  Future<void> cancelAll() async {
    try {
      await _plugin.cancelAll();
    } catch (error) {
      _logFailure('cancelAll', error);
    }
  }

  /// Queries the current OS-level notification permission status.
  /// Returns [NotificationPermissionStatus.unknown] on platforms/plugin
  /// versions where this cannot be reliably queried, rather than guessing.
  Future<NotificationPermissionStatus> permissionStatus() async {
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android != null) {
        final enabled = await android.areNotificationsEnabled();
        if (enabled == null) return NotificationPermissionStatus.unknown;
        return enabled
            ? NotificationPermissionStatus.granted
            : NotificationPermissionStatus.denied;
      }

      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      if (ios != null) {
        final options = await ios.checkPermissions();
        if (options == null) return NotificationPermissionStatus.unknown;
        return options.isEnabled
            ? NotificationPermissionStatus.granted
            : NotificationPermissionStatus.denied;
      }

      final macos = _plugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >();
      if (macos != null) {
        final options = await macos.checkPermissions();
        if (options == null) return NotificationPermissionStatus.unknown;
        return options.isEnabled
            ? NotificationPermissionStatus.granted
            : NotificationPermissionStatus.denied;
      }
    } catch (error) {
      _logFailure('permissionStatus', error);
    }
    return NotificationPermissionStatus.unknown;
  }

  /// Requests notification permission from the user, if the current
  /// platform supports an explicit request call. Returns whether permission
  /// was granted; never throws — a plugin/platform error is treated as "not
  /// granted" rather than surfaced as a raw exception.
  Future<bool> requestPermission() async {
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android != null) {
        return await android.requestNotificationsPermission() ?? false;
      }

      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      if (ios != null) {
        return await ios.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ) ??
            false;
      }

      final macos = _plugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >();
      if (macos != null) {
        return await macos.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ) ??
            false;
      }
    } catch (error) {
      _logFailure('requestPermission', error);
    }
    return false;
  }

  /// Returns the next [tz.TZDateTime] that falls on [weekday] (ISO 1–7) at
  /// [time]. Searches forward from today's candidate, at most 7 days ahead.
  tz.TZDateTime _nextInstanceOf(TimeOfDay time, int weekday) {
    final now = DateTime.now();
    var candidate = DateTime(
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );
    for (var i = 0; i < 7; i++) {
      final d = candidate.add(Duration(days: i));
      if (d.weekday == weekday && !d.isBefore(now)) {
        return tz.TZDateTime.from(d, tz.UTC);
      }
    }
    // Fallback: jump ahead to the target weekday next week.
    final daysAhead = (weekday - candidate.weekday + 7) % 7;
    final next = candidate.add(Duration(days: daysAhead == 0 ? 7 : daysAhead));
    return tz.TZDateTime.from(next, tz.UTC);
  }
}
