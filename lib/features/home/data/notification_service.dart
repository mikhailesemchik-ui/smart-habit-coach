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

/// Schedules and cancels daily local reminders for habits.
/// This wraps `flutter_local_notifications` so it can be swapped or faked
/// independently of the UI. Does not perform timezone-aware scheduling
/// beyond the device's current local time offset.
class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

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
      debugPrint('NotificationService.initialize failed: $error');
    }
  }

  Future<void> scheduleHabitReminder(Habit habit) async {
    final time = parseScheduledTime(habit.scheduledTime);
    if (time == null) return;

    try {
      await _plugin.zonedSchedule(
        id: stableNotificationId(habit.id),
        title: habit.title,
        body: 'Time to complete your habit',
        scheduledDate: _nextInstanceOf(time),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'habit_reminders',
            'Habit reminders',
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (error) {
      debugPrint('NotificationService.scheduleHabitReminder failed: $error');
    }
  }

  Future<void> cancelHabitReminder(String habitId) async {
    try {
      await _plugin.cancel(id: stableNotificationId(habitId));
    } catch (error) {
      debugPrint('NotificationService.cancelHabitReminder failed: $error');
    }
  }

  tz.TZDateTime _nextInstanceOf(TimeOfDay time) {
    final now = DateTime.now();
    var scheduled = DateTime(
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return tz.TZDateTime.from(scheduled, tz.UTC);
  }
}
