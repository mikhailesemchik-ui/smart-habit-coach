import 'package:flutter/material.dart';

import '../../ai_habit_setup/presentation/ai_habit_setup_sheet.dart';
import '../data/habit_storage.dart';
import '../data/notification_service.dart';
import '../domain/date_key.dart';
import '../domain/habit.dart';
import '../domain/sample_habits.dart';
import 'add_habit_sheet.dart';
import 'habit_details_sheet.dart';

const _weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

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

class HomeScreen extends StatefulWidget {
  final NotificationService? notificationService;

  const HomeScreen({super.key, this.notificationService});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final HabitStorage _storage = HabitStorage();
  late final NotificationService _notifications =
      widget.notificationService ?? NotificationService();
  List<Habit> _habits = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _notifications.initialize();
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

  void _toggleHabit(String id) {
    setState(() {
      final index = _habits.indexWhere((habit) => habit.id == id);
      _habits[index] = _habits[index].toggleDate(todayKey());
    });
    _storage.saveHabits(_habits);
  }

  void _addHabit(Habit habit) {
    setState(() => _habits.add(habit));
    _storage.saveHabits(_habits);
    _notifications.scheduleHabitReminder(habit);
  }

  Future<void> _openAddHabitSheet() async {
    final newHabit = await showModalBottomSheet<Habit>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const AddHabitSheet(),
    );

    if (newHabit != null) {
      _addHabit(newHabit);
    }
  }

  Future<void> _openEditHabitSheet(Habit habit) async {
    final updated = await showModalBottomSheet<Habit>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AddHabitSheet(initialHabit: habit),
    );

    if (updated != null) {
      setState(() {
        final index = _habits.indexWhere((h) => h.id == habit.id);
        _habits[index] = updated;
      });
      _storage.saveHabits(_habits);
      _notifications.scheduleHabitReminder(updated);
    }
  }

  Future<void> _confirmDeleteHabit(Habit habit) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete habit'),
        content: Text('Delete "${habit.title}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _habits.removeWhere((h) => h.id == habit.id));
      _storage.saveHabits(_habits);
      _notifications.cancelHabitReminder(habit.id);
    }
  }

  Future<void> _openAiHabitSetup() async {
    final result = await showModalBottomSheet<AiHabitSetupResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const AiHabitSetupSheet(),
    );

    if (result == null) return;
    if (!mounted) return;

    if (result.openForEditing) {
      final edited = await showModalBottomSheet<Habit>(
        context: context,
        isScrollControlled: true,
        builder: (_) => AddHabitSheet(initialHabit: result.habit),
      );
      if (edited == null) return;
      _addHabit(edited);
    } else {
      _addHabit(result.habit);
    }
  }

  Future<void> _openHabitDetails(Habit habit) async {
    final action = await showModalBottomSheet<HabitDetailsAction>(
      context: context,
      builder: (_) => HabitDetailsSheet(habit: habit),
    );

    if (action == HabitDetailsAction.edit) {
      await _openEditHabitSheet(habit);
    } else if (action == HabitDetailsAction.delete) {
      await _confirmDeleteHabit(habit);
    }
  }

  String _formatToday() {
    final now = DateTime.now();
    final weekday = _weekdayNames[now.weekday - 1];
    final month = _monthNames[now.month - 1];
    return '$weekday, $month ${now.day}';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Today')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final completedCount = _habits
        .where((habit) => habit.isCompletedToday)
        .length;

    return Scaffold(
      appBar: AppBar(title: const Text('Today')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(_formatToday(), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          _ProgressCard(
            completedCount: completedCount,
            totalCount: _habits.length,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _openAiHabitSetup,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Create with AI'),
            ),
          ),
          const SizedBox(height: 16),
          for (final habit in _habits)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _HabitCard(
                habit: habit,
                onToggle: () => _toggleHabit(habit.id),
                onTap: () => _openHabitDetails(habit),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddHabitSheet,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  final int completedCount;
  final int totalCount;

  const _ProgressCard({required this.completedCount, required this.totalCount});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = totalCount == 0 ? 0.0 : completedCount / totalCount;
    final percentage = (progress * 100).round();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Today\'s progress', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 8),
            Text(
              '$completedCount of $totalCount habits completed ($percentage%)',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _HabitCard extends StatelessWidget {
  final Habit habit;
  final VoidCallback onToggle;
  final VoidCallback onTap;

  const _HabitCard({
    required this.habit,
    required this.onToggle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: ListTile(
        onTap: onTap,
        leading: Icon(habit.icon, color: theme.colorScheme.primary),
        title: Text(habit.title),
        subtitle: Text(habit.scheduledTime),
        trailing: IconButton(
          icon: Icon(
            habit.isCompletedToday
                ? Icons.check_circle
                : Icons.radio_button_unchecked,
            color: habit.isCompletedToday ? theme.colorScheme.primary : null,
          ),
          onPressed: onToggle,
        ),
      ),
    );
  }
}
