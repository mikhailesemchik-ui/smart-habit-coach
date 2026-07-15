import 'package:flutter/material.dart';

import '../../../app/theme/app_radii.dart';
import '../../coach/presentation/coach_insights_screen.dart';
import '../../home/data/habit_storage.dart';
import '../../home/domain/habit.dart';
import '../../home/domain/sample_habits.dart';
import '../domain/progress_stats.dart';
import '../domain/weekly_review.dart';
import 'day_history_sheet.dart';
import 'habit_history_calendar_sheet.dart';
import 'weekly_review_sheet.dart';

const _weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  final HabitStorage _storage = HabitStorage();
  List<Habit> _habits = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHabits();
  }

  Future<void> _loadHabits() async {
    final savedHabits = await _storage.loadHabits();
    if (!mounted) return;
    setState(() {
      _habits = savedHabits ?? sampleHabits();
      _isLoading = false;
    });
  }

  // Merges [updatedActive] back into the full habit list.
  // Used by calendar/history sheets that receive only active habits.
  void _mergeActiveHabits(List<Habit> updatedActive) {
    final updatedMap = {for (final h in updatedActive) h.id: h};
    setState(
      () => _habits = _habits.map((h) => updatedMap[h.id] ?? h).toList(),
    );
  }

  void _openCalendar() {
    final activeHabits = _habits.where((h) => h.isActive).toList();
    // Capture the parent screen's ScaffoldMessenger so DayHistorySheet (opened
    // from inside HabitHistoryCalendarSheet) shows SnackBars on the correct
    // Scaffold rather than whatever the root messenger happens to pick.
    final messenger = ScaffoldMessenger.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => HabitHistoryCalendarSheet(
        habits: activeHabits,
        today: DateTime.now(),
        onHabitsChanged: (updated) {
          if (!mounted) return;
          _mergeActiveHabits(updated);
        },
        scaffoldMessenger: messenger,
      ),
    );
  }

  void _openDayHistory(DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (day.isAfter(today)) return;

    final activeHabits = _habits.where((h) => h.isActive).toList();
    // Capture the parent screen's ScaffoldMessenger before opening the modal.
    final messenger = ScaffoldMessenger.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DayHistorySheet(
        day: day,
        habits: activeHabits,
        onHabitsChanged: (updated) {
          if (!mounted) return;
          _mergeActiveHabits(updated);
        },
        scaffoldMessenger: messenger,
      ),
    );
  }

  Future<void> _openWeeklyReview() async {
    final now = DateTime.now();
    final activeHabits = _habits.where((h) => h.isActive).toList();
    final localReview = generateWeeklyReview(activeHabits, now);
    final metrics = calculateWeeklyReviewMetrics(activeHabits, now);
    await showModalBottomSheet<void>(
      context: context,
      builder: (_) => WeeklyReviewSheet(
        localReview: localReview,
        metrics: metrics,
        habits: _habits,
        onHabitUpdated: (updated) {
          if (!mounted) return;
          _mergeActiveHabits([updated]);
        },
      ),
    );
  }

  void _openCoachInsights() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const CoachInsightsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Progress')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_habits.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Progress')),
        body: const Center(child: Text('Add a habit to see your progress')),
      );
    }

    final now = DateTime.now();
    // Paused and archived habits are excluded from all Progress calculations.
    final activeHabits = _habits.where((h) => h.isActive).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Progress')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _StatsCard(
            rate: weeklyCompletionRate(activeHabits, now),
            streak: currentStreak(activeHabits, now),
            bestStreak: bestStreak(activeHabits, now),
          ),
          const SizedBox(height: 16),
          _WeekSummary(
            habits: activeHabits,
            days: last7Days(now),
            onDayTap: _openDayHistory,
            onOpenCalendar: _openCalendar,
          ),
          const SizedBox(height: 16),
          _WeeklyReviewCard(onOpenReview: _openWeeklyReview),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.history),
            title: const Text('Coach Insights'),
            subtitle: const Text(
              'Your habit plan adjustments and recent coaching history',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openCoachInsights,
          ),
        ],
      ),
    );
  }
}

class _WeeklyReviewCard extends StatelessWidget {
  final VoidCallback onOpenReview;

  const _WeeklyReviewCard({required this.onOpenReview});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Weekly review', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'See what went well, partial progress, patterns, and one focus for next week.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: onOpenReview,
                child: const Text('View weekly review'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  final double rate;
  final int streak;
  final int bestStreak;

  const _StatsCard({
    required this.rate,
    required this.streak,
    required this.bestStreak,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percentage = (rate * 100).round();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Last 7 days', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: rate),
            const SizedBox(height: 8),
            Text(
              '$percentage% completion rate',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _StreakTile(label: 'Current streak', value: streak),
                ),
                Expanded(
                  child: _StreakTile(label: 'Best streak', value: bestStreak),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StreakTile extends StatelessWidget {
  final String label;
  final int value;

  const _StreakTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.bodySmall),
        Text('$value', style: theme.textTheme.headlineSmall),
      ],
    );
  }
}

class _WeekSummary extends StatelessWidget {
  final List<Habit> habits;
  final List<DateTime> days;
  final void Function(DateTime) onDayTap;
  final VoidCallback onOpenCalendar;

  const _WeekSummary({
    required this.habits,
    required this.days,
    required this.onDayTap,
    required this.onOpenCalendar,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text('This week', style: theme.textTheme.titleMedium),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: onOpenCalendar,
                  child: const Text('View calendar'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final day in days)
                  _DayIndicator(
                    day: day,
                    habits: habits,
                    onTap: () => onDayTap(day),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DayIndicator extends StatelessWidget {
  final DateTime day;
  final List<Habit> habits;
  final VoidCallback onTap;

  const _DayIndicator({
    required this.day,
    required this.habits,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheduledCount = habits.where((h) => h.isScheduledFor(day)).length;
    final count = dailyCompletionCount(habits, day);
    final hasScheduled = scheduledCount > 0;
    final allDone = hasScheduled && count == scheduledCount;
    final anyDone = count > 0;

    return InkWell(
      onTap: onTap,
      borderRadius: AppRadii.smallRadius,
      child: Column(
        children: [
          Text(
            _weekdayLabels[day.weekday - 1],
            style: theme.textTheme.labelSmall,
          ),
          const SizedBox(height: 6),
          CircleAvatar(
            radius: 14,
            backgroundColor: allDone
                ? theme.colorScheme.primary
                : anyDone
                ? theme.colorScheme.primary.withValues(alpha: 0.35)
                : theme.colorScheme.surfaceContainerHighest,
            child: allDone
                ? Icon(
                    Icons.check,
                    size: 16,
                    color: theme.colorScheme.onPrimary,
                  )
                : null,
          ),
        ],
      ),
    );
  }
}
