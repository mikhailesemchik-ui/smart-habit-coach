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
  late List<Habit> _habits;
  late final String _dateKey;

  @override
  void initState() {
    super.initState();
    _habits = List.of(widget.habits);
    _dateKey = dateKey(widget.day);
  }

  Future<void> _toggle(int index) async {
    final updated = List<Habit>.of(_habits);
    updated[index] = updated[index].toggleDate(_dateKey);
    await _storage.saveHabits(updated);
    if (!mounted) return;
    setState(() => _habits = updated);
    widget.onHabitsChanged(updated);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final completedCount = _habits
        .where((h) => h.isCompletedOn(_dateKey))
        .length;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.75;

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
              child: _habits.isEmpty
                  ? const SizedBox.shrink()
                  : Text(
                      '$completedCount of ${_habits.length} completed',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
            ),
            const Divider(height: 1),
            Flexible(
              child: _habits.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          'No habits yet',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _habits.length,
                      itemBuilder: (_, index) {
                        final habit = _habits[index];
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
