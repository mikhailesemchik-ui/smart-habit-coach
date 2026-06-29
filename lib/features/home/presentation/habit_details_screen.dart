import 'package:flutter/material.dart';

import '../data/habit_storage.dart';
import '../data/notification_service.dart';
import '../domain/date_key.dart';
import '../domain/habit.dart';
import '../domain/habit_stats.dart';
import 'add_habit_sheet.dart';

const _weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

int _daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;
int _firstWeekdayOffset(int year, int month) =>
    DateTime(year, month, 1).weekday - 1;

class HabitDetailsScreen extends StatefulWidget {
  final Habit habit;
  final NotificationService? notificationService;

  /// Reference date used as "today". Injected so tests can use fixed dates.
  final DateTime? today;

  const HabitDetailsScreen({
    super.key,
    required this.habit,
    this.notificationService,
    this.today,
  });

  @override
  State<HabitDetailsScreen> createState() => _HabitDetailsScreenState();
}

class _HabitDetailsScreenState extends State<HabitDetailsScreen> {
  late Habit _habit;
  late NotificationService _notifications;
  late DateTime _today;
  late DateTime _displayedMonth;
  final HabitStorage _storage = HabitStorage();

  @override
  void initState() {
    super.initState();
    _habit = widget.habit;
    _notifications = widget.notificationService ?? NotificationService();
    final now = widget.today ?? DateTime.now();
    _today = DateTime(now.year, now.month, now.day);
    _displayedMonth = DateTime(_today.year, _today.month, 1);
  }

  Future<void> _toggle(DateTime day) async {
    if (day.isAfter(_today)) return;
    final key = dateKey(day);
    final Habit updated;
    if (_habit.hasMinimumVersion) {
      // Cycle: none → full → minimum → none
      final next = switch (_habit.completionStatusFor(key)) {
        HabitCompletionStatus.none => HabitCompletionStatus.full,
        HabitCompletionStatus.full => HabitCompletionStatus.minimum,
        HabitCompletionStatus.minimum => HabitCompletionStatus.none,
      };
      updated = _habit.setCompletionStatus(key, next);
    } else {
      updated = _habit.toggleDate(key);
    }
    setState(() => _habit = updated);
    await _persistHabit(updated);
  }

  Future<void> _persistHabit(Habit habit) async {
    final all = await _storage.loadHabits() ?? [];
    final idx = all.indexWhere((h) => h.id == habit.id);
    if (idx == -1) {
      all.add(habit);
    } else {
      all[idx] = habit;
    }
    await _storage.saveHabits(all);
  }

  void _previousMonth() {
    setState(() {
      final m = _displayedMonth.month;
      final y = _displayedMonth.year;
      _displayedMonth = m == 1 ? DateTime(y - 1, 12, 1) : DateTime(y, m - 1, 1);
    });
  }

  void _nextMonth() {
    setState(() {
      final m = _displayedMonth.month;
      final y = _displayedMonth.year;
      _displayedMonth = m == 12 ? DateTime(y + 1, 1, 1) : DateTime(y, m + 1, 1);
    });
  }

  Future<void> _editHabit() async {
    final updated = await showModalBottomSheet<Habit>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AddHabitSheet(initialHabit: _habit),
    );
    if (updated == null || !mounted) return;
    setState(() => _habit = updated);
    await _persistHabit(updated);
    // Only reschedule if the habit is still active.
    if (updated.isActive) {
      await _notifications.scheduleHabitReminder(updated);
    }
  }

  Future<void> _pauseHabit() async {
    final paused = _habit.asPaused(dateKey(_today));
    setState(() => _habit = paused);
    await _persistHabit(paused);
    await _notifications.cancelHabitReminder(paused.id);
  }

  Future<void> _resumeHabit() async {
    final resumed = _habit.asActive();
    setState(() => _habit = resumed);
    await _persistHabit(resumed);
    await _notifications.scheduleHabitReminder(resumed);
  }

  Future<void> _archiveHabit() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archive habit'),
        content: Text(
          'Archive "${_habit.title}"? It will be hidden from Today '
          'but you can restore it later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final archived = _habit.asArchived(dateKey(_today));
    setState(() => _habit = archived);
    await _persistHabit(archived);
    await _notifications.cancelHabitReminder(archived.id);
  }

  Future<void> _restoreHabit() async {
    final restored = _habit.asActive();
    setState(() => _habit = restored);
    await _persistHabit(restored);
    await _notifications.scheduleHabitReminder(restored);
  }

  Future<void> _deleteHabit() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete habit'),
        content: Text('Delete "${_habit.title}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final all = await _storage.loadHabits() ?? [];
    all.removeWhere((h) => h.id == _habit.id);
    await _storage.saveHabits(all);
    await _notifications.cancelHabitReminder(_habit.id);
    if (mounted) Navigator.of(context).pop();
  }

  String _repeatLabel() {
    if (_habit.weekdays.length == 7) return 'Every day';
    return _habit.weekdays.map((d) => _weekdayLabels[d - 1]).join(', ');
  }

  String _pluralDays(int n) => '$n ${n == 1 ? "day" : "days"}';

  String _statusLabel() {
    return switch (_habit.status) {
      HabitStatus.active => 'Active',
      HabitStatus.paused => 'Paused',
      HabitStatus.archived => 'Archived',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_habit.title)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSummaryCard(theme),
            const SizedBox(height: 16),
            _buildStatsCard(theme),
            const SizedBox(height: 16),
            _buildCalendarSection(theme),
            const SizedBox(height: 24),
            _buildActions(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(ThemeData theme) {
    final statusLabel = _statusLabel();
    final statusColor = switch (_habit.status) {
      HabitStatus.active => theme.colorScheme.primary,
      HabitStatus.paused => theme.colorScheme.tertiary,
      HabitStatus.archived => theme.colorScheme.onSurfaceVariant,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_habit.icon, color: theme.colorScheme.primary, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(_habit.title, style: theme.textTheme.titleLarge),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    statusLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _LabelValue(label: 'Reminder', value: _habit.scheduledTime),
            const SizedBox(height: 4),
            _LabelValue(label: 'Repeat', value: _repeatLabel()),
            if (_habit.hasMinimumVersion) ...[
              const SizedBox(height: 4),
              _LabelValue(label: 'Minimum', value: _habit.minimumVersion!),
            ],
            const SizedBox(height: 4),
            _LabelValue(
              label: 'Today',
              value: switch (_habit.completionStatusFor(dateKey(_today))) {
                HabitCompletionStatus.full => 'Completed',
                HabitCompletionStatus.minimum => 'Minimum done',
                HabitCompletionStatus.none => 'Not completed',
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsCard(ThemeData theme) {
    final streak = habitCurrentStreak(_habit, _today);
    final best = habitBestStreak(_habit, _today);
    final rate = habitCompletionRate(_habit, _today);
    final total = habitTotalCompleted(_habit);
    final minCount = habitMinimumCompletedCount(_habit);
    final consistencyRate = habitConsistencyRate(_habit, _today);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Statistics', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _StatTile(
                    label: 'Current streak',
                    value: _pluralDays(streak),
                  ),
                ),
                Expanded(
                  child: _StatTile(
                    label: 'Best streak',
                    value: _pluralDays(best),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _StatTile(
                    label: 'Last 30 days',
                    value: '${(rate * 100).round()}%',
                  ),
                ),
                Expanded(
                  child: _StatTile(label: 'Total done', value: '$total'),
                ),
              ],
            ),
            if (_habit.hasMinimumVersion) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _StatTile(label: 'Minimum done', value: '$minCount'),
                  ),
                  Expanded(
                    child: _StatTile(
                      label: 'Consistency',
                      value: '${(consistencyRate * 100).round()}%',
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCalendarSection(ThemeData theme) {
    final year = _displayedMonth.year;
    final month = _displayedMonth.month;
    final offset = _firstWeekdayOffset(year, month);
    final days = _daysInMonth(year, month);
    final totalCells = ((offset + days + 6) ~/ 7) * 7;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              tooltip: 'Previous month',
              onPressed: _previousMonth,
            ),
            Expanded(
              child: Text(
                '${_monthNames[month - 1]} $year',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              tooltip: 'Next month',
              onPressed: _nextMonth,
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: _weekdayLabels.map((label) {
              return Expanded(
                child: Center(
                  child: Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 4),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisExtent: 40,
          ),
          itemCount: totalCells,
          itemBuilder: (_, index) {
            if (index < offset || index >= offset + days) {
              return const SizedBox.shrink();
            }
            final dayNumber = index - offset + 1;
            final day = DateTime(year, month, dayNumber);
            final isFuture = day.isAfter(_today);
            final isToday = day == _today;
            final isScheduled = _habit.isScheduledFor(day);
            final dayStatus = _habit.completionStatusFor(dateKey(day));

            return _CalendarDayCell(
              day: day,
              isScheduled: isScheduled,
              isCompleted: dayStatus == HabitCompletionStatus.full,
              isMinimum: dayStatus == HabitCompletionStatus.minimum,
              isToday: isToday,
              isFuture: isFuture,
              onTap: (isFuture || !isScheduled) ? null : () => _toggle(day),
            );
          },
        ),
      ],
    );
  }

  Widget _buildActions(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: _editHabit,
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Edit habit'),
        ),
        const SizedBox(height: 8),
        if (_habit.status == HabitStatus.active) ...[
          OutlinedButton.icon(
            onPressed: _pauseHabit,
            icon: const Icon(Icons.pause_outlined),
            label: const Text('Pause habit'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _archiveHabit,
            icon: const Icon(Icons.archive_outlined),
            label: const Text('Archive habit'),
          ),
        ] else if (_habit.status == HabitStatus.paused) ...[
          FilledButton.icon(
            onPressed: _resumeHabit,
            icon: const Icon(Icons.play_arrow_outlined),
            label: const Text('Resume habit'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _archiveHabit,
            icon: const Icon(Icons.archive_outlined),
            label: const Text('Archive habit'),
          ),
        ] else if (_habit.status == HabitStatus.archived) ...[
          FilledButton.icon(
            onPressed: _restoreHabit,
            icon: const Icon(Icons.unarchive_outlined),
            label: const Text('Restore habit'),
          ),
        ],
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _deleteHabit,
          icon: const Icon(Icons.delete_outline),
          label: const Text('Delete habit'),
          style: OutlinedButton.styleFrom(
            foregroundColor: theme.colorScheme.error,
            side: BorderSide(color: theme.colorScheme.error),
          ),
        ),
      ],
    );
  }
}

class _LabelValue extends StatelessWidget {
  final String label;
  final String value;

  const _LabelValue({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;

  const _StatTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: theme.textTheme.headlineSmall?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _CalendarDayCell extends StatelessWidget {
  final DateTime day;
  final bool isScheduled;
  final bool isCompleted;
  final bool isMinimum;
  final bool isToday;
  final bool isFuture;
  final VoidCallback? onTap;

  const _CalendarDayCell({
    required this.day,
    required this.isScheduled,
    required this.isCompleted,
    required this.isMinimum,
    required this.isToday,
    required this.isFuture,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final Color bg;
    final Color textColor;

    if (isFuture) {
      bg = Colors.transparent;
      textColor = cs.onSurface.withValues(alpha: 0.3);
    } else if (!isScheduled) {
      bg = Colors.transparent;
      textColor = cs.onSurface.withValues(alpha: 0.45);
    } else if (isCompleted) {
      bg = cs.primary;
      textColor = cs.onPrimary;
    } else if (isMinimum) {
      bg = cs.tertiary.withValues(alpha: 0.25);
      textColor = cs.tertiary;
    } else {
      bg = cs.error.withValues(alpha: 0.15);
      textColor = cs.error;
    }

    return GestureDetector(
      onTap: onTap,
      child: Center(
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: bg,
            border: isToday ? Border.all(color: cs.primary, width: 1.5) : null,
          ),
          child: Center(
            child: Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: isToday ? FontWeight.w600 : FontWeight.normal,
                color: textColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
