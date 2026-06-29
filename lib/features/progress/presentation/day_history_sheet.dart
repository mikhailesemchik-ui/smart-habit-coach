import 'package:flutter/material.dart';

import '../../home/data/habit_storage.dart';
import '../../home/domain/date_key.dart';
import '../../home/domain/habit.dart';

const _monthAbbrevs = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

const _weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

String formatSheetDate(DateTime day) =>
    '${_weekdayNames[day.weekday - 1]}, ${_monthAbbrevs[day.month - 1]} ${day.day}';

class DayHistorySheet extends StatefulWidget {
  final DateTime day;
  final List<Habit> habits;
  final void Function(List<Habit>) onHabitsChanged;

  const DayHistorySheet({
    super.key,
    required this.day,
    required this.habits,
    required this.onHabitsChanged,
  });

  @override
  State<DayHistorySheet> createState() => _DayHistorySheetState();
}

class _DayHistorySheetState extends State<DayHistorySheet> {
  final _storage = HabitStorage();

  /// Full habit list — used for saves and callbacks.
  late List<Habit> _allHabits;

  /// Habits scheduled for [widget.day] — displayed in the list.
  late List<Habit> _scheduled;

  late final String _dateKey;

  @override
  void initState() {
    super.initState();
    _allHabits = List.of(widget.habits);
    _dateKey = dateKey(widget.day);
    _scheduled = _allHabits.where((h) => h.isScheduledFor(widget.day)).toList();
  }

  Future<void> _toggle(int scheduledIndex) async {
    final habit = _scheduled[scheduledIndex];
    final allIndex = _allHabits.indexWhere((h) => h.id == habit.id);
    final updated = List<Habit>.of(_allHabits);
    updated[allIndex] = updated[allIndex].toggleDate(_dateKey);
    await _storage.saveHabits(updated);
    if (!mounted) return;
    setState(() {
      _allHabits = updated;
      _scheduled = _allHabits
          .where((h) => h.isScheduledFor(widget.day))
          .toList();
    });
    widget.onHabitsChanged(updated);
  }

  Future<void> _setStatus(
    int scheduledIndex,
    HabitCompletionStatus status,
  ) async {
    final habit = _scheduled[scheduledIndex];
    final allIndex = _allHabits.indexWhere((h) => h.id == habit.id);
    final updated = List<Habit>.of(_allHabits);
    updated[allIndex] = updated[allIndex].setCompletionStatus(_dateKey, status);
    await _storage.saveHabits(updated);
    if (!mounted) return;
    setState(() {
      _allHabits = updated;
      _scheduled = _allHabits
          .where((h) => h.isScheduledFor(widget.day))
          .toList();
    });
    widget.onHabitsChanged(updated);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final completedCount = _scheduled
        .where((h) => h.isCompletedOn(_dateKey))
        .length;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.75;

    String? emptyMessage;
    if (_allHabits.isEmpty) {
      emptyMessage = 'No habits yet';
    } else if (_scheduled.isEmpty) {
      emptyMessage = 'No habits scheduled';
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Container(
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
              child: Text(
                formatSheetDate(widget.day),
                style: theme.textTheme.titleMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: _scheduled.isEmpty
                  ? const SizedBox.shrink()
                  : Text(
                      '$completedCount of ${_scheduled.length} completed',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
            ),
            const Divider(height: 1),
            Flexible(
              child: emptyMessage != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          emptyMessage,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _scheduled.length,
                      itemBuilder: (_, index) {
                        final habit = _scheduled[index];
                        if (habit.hasMinimumVersion) {
                          return _MinVersionTile(
                            habit: habit,
                            dateKey: _dateKey,
                            onChanged: (s) => _setStatus(index, s),
                          );
                        }
                        return CheckboxListTile(
                          secondary: Icon(habit.icon),
                          title: Text(habit.title),
                          value: habit.isCompletedOn(_dateKey),
                          onChanged: (_) => _toggle(index),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Three-state list tile for habits that have a minimum version configured.
class _MinVersionTile extends StatelessWidget {
  final Habit habit;
  final String dateKey;
  final void Function(HabitCompletionStatus) onChanged;

  const _MinVersionTile({
    required this.habit,
    required this.dateKey,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final status = habit.completionStatusFor(dateKey);

    return ListTile(
      leading: Icon(habit.icon),
      title: Text(habit.title),
      subtitle: status == HabitCompletionStatus.minimum
          ? Text('Minimum done', style: TextStyle(color: cs.tertiary))
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StatusIconButton(
            icon: Icons.radio_button_unchecked,
            selected: status == HabitCompletionStatus.none,
            color: cs.onSurfaceVariant,
            onTap: () => onChanged(HabitCompletionStatus.none),
          ),
          _StatusIconButton(
            icon: Icons.adjust,
            selected: status == HabitCompletionStatus.minimum,
            color: cs.tertiary,
            onTap: () => onChanged(HabitCompletionStatus.minimum),
          ),
          _StatusIconButton(
            icon: Icons.check_circle,
            selected: status == HabitCompletionStatus.full,
            color: cs.primary,
            onTap: () => onChanged(HabitCompletionStatus.full),
          ),
        ],
      ),
    );
  }
}

class _StatusIconButton extends StatelessWidget {
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _StatusIconButton({
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dimColor = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.38);
    return IconButton(
      icon: Icon(icon, color: selected ? color : dimColor),
      onPressed: onTap,
      iconSize: 20,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      padding: EdgeInsets.zero,
    );
  }
}
