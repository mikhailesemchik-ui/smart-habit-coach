import '../domain/habit.dart';
import 'habit_storage.dart';
import 'notification_service.dart';

/// Reconciles scheduled local reminders with the currently-active local
/// namespace's habit data.
///
/// Cancels every existing scheduled reminder first, then reschedules one
/// only for each habit that is active (not paused, not archived, not
/// tombstoned) in the current namespace. This is what keeps reminders
/// correct across an account/UID switch: reminders scheduled under a
/// previously-active identity are never left behind to fire for the wrong
/// account, since [HabitStorage] itself is namespaced and only ever reads
/// the currently-active identity's habits.
class NotificationReconciliationService {
  final HabitStorage _storage;
  final NotificationService _notifications;

  NotificationReconciliationService({
    HabitStorage? storage,
    NotificationService? notifications,
  }) : _storage = storage ?? HabitStorage(),
       _notifications = notifications ?? NotificationService();

  /// Cancels all scheduled reminders, then reschedules reminders for every
  /// active, non-archived, non-tombstoned habit in the current namespace.
  Future<void> reconcile() async {
    await _notifications.cancelAll();
    final habits = await _storage.loadHabits();
    if (habits == null) return;
    for (final habit in habits) {
      if (habit.status == HabitStatus.active) {
        await _notifications.scheduleHabitReminder(habit);
      }
    }
  }
}
