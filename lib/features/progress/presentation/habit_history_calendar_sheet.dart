import 'package:flutter/material.dart';

import '../../home/domain/habit.dart';
import '../domain/progress_stats.dart';
import 'day_history_sheet.dart';

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

const _weekdayHeaders = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Number of days in [month] of [year]. Handles leap years correctly.
int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// Zero-based weekday offset of the first day of [month] in [year].
/// 0 = Monday … 6 = Sunday.
int firstWeekdayOffset(int year, int month) =>
    DateTime(year, month, 1).weekday - 1;

class HabitHistoryCalendarSheet extends StatefulWidget {
  final List<Habit> habits;

  /// Reference date used as "today". Injected so tests can use fixed dates.
  final DateTime today;
  final void Function(List<Habit>) onHabitsChanged;

  const HabitHistoryCalendarSheet({
    super.key,
    required this.habits,
    required this.today,
    required this.onHabitsChanged,
  });

  @override
  State<HabitHistoryCalendarSheet> createState() =>
      _HabitHistoryCalendarSheetState();
}

class _HabitHistoryCalendarSheetState extends State<HabitHistoryCalendarSheet> {
  late List<Habit> _habits;
  late final DateTime _today; // normalized to midnight
  late DateTime _displayedMonth; // always the 1st of the displayed month

  @override
  void initState() {
    super.initState();
    _habits = List.of(widget.habits);
    _today = DateTime(widget.today.year, widget.today.month, widget.today.day);
    _displayedMonth = DateTime(_today.year, _today.month, 1);
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

  void _onDayTap(DateTime day) {
    if (day.isAfter(_today)) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DayHistorySheet(
        day: day,
        habits: _habits,
        onHabitsChanged: (updated) {
          if (!mounted) return;
          setState(() => _habits = updated);
          widget.onHabitsChanged(updated);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final year = _displayedMonth.year;
    final month = _displayedMonth.month;
    final offset = firstWeekdayOffset(year, month);
    final days = daysInMonth(year, month);
    final totalCells = ((offset + days + 6) ~/ 7) * 7;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.9;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
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
              // Month navigation
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                child: Row(
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
              ),
              // Weekday header row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: _weekdayHeaders.map((label) {
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
              // Day grid
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: GridView.builder(
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
                    final isToday = day == _today;
                    final isFuture = day.isAfter(_today);
                    return _CalendarDayCell(
                      day: day,
                      habits: _habits,
                      isToday: isToday,
                      isFuture: isFuture,
                      onTap: isFuture ? null : () => _onDayTap(day),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CalendarDayCell extends StatelessWidget {
  final DateTime day;
  final List<Habit> habits;
  final bool isToday;
  final bool isFuture;
  final VoidCallback? onTap;

  const _CalendarDayCell({
    required this.day,
    required this.habits,
    required this.isToday,
    required this.isFuture,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = dailyCompletionCount(habits, day);
    final allDone = habits.isNotEmpty && count == habits.length;
    final anyDone = count > 0;

    final Color bg;
    final Color textColor;

    if (isFuture) {
      bg = Colors.transparent;
      textColor = theme.colorScheme.onSurface.withValues(alpha: 0.3);
    } else if (allDone) {
      bg = theme.colorScheme.primary;
      textColor = theme.colorScheme.onPrimary;
    } else if (anyDone) {
      bg = theme.colorScheme.primary.withValues(alpha: 0.35);
      textColor = theme.colorScheme.onSurface;
    } else {
      bg = Colors.transparent;
      textColor = theme.colorScheme.onSurface;
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
            border: (isToday && !allDone)
                ? Border.all(color: theme.colorScheme.primary, width: 1.5)
                : null,
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
