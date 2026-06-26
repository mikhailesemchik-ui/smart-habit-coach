import 'package:flutter/material.dart';

import '../../home/data/habit_storage.dart';
import '../../home/domain/habit.dart';
import '../../home/domain/sample_habits.dart';
import '../domain/progress_stats.dart';
import '../domain/weekly_review.dart';
import 'day_history_sheet.dart';
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

  void _openDayHistory(DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (day.isAfter(today)) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DayHistorySheet(
        day: day,
        habits: _habits,
        onHabitsChanged: (updated) {
          if (!mounted) return;
          setState(() => _habits = updated);
        },
      ),
    );
  }

  Future<void> _openWeeklyReview() async {
    final now = DateTime.now();
    final localReview = generateWeeklyReview(_habits, now);
    final metrics = calculateWeeklyReviewMetrics(_habits, now);
    await showModalBottomSheet<void>(
      context: context,
      builder: (_) =>
          WeeklyReviewSheet(localReview: localReview, metrics: metrics),
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

    return Scaffold(
      appBar: AppBar(title: const Text('Progress')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _StatsCard(
            rate: weeklyCompletionRate(_habits, now),
            streak: currentStreak(_habits, now),
            bestStreak: bestStreak(_habits, now),
          ),
          const SizedBox(height: 16),
          _WeekSummary(
            habits: _habits,
            days: last7Days(now),
            onDayTap: _openDayHistory,
          ),
          const SizedBox(height: 16),
          _WeeklyReviewCard(onOpenReview: _openWeeklyReview),
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
              'See your strongest and weakest day, plus a recommendation for next week.',
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

  const _WeekSummary({
    required this.habits,
    required this.days,
    required this.onDayTap,
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
            Text('This week', style: theme.textTheme.titleMedium),
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
    final count = dailyCompletionCount(habits, day);
    final allDone = habits.isNotEmpty && count == habits.length;
    final anyDone = count > 0;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
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
