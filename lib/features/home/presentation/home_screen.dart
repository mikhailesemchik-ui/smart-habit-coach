import 'package:flutter/material.dart';

import '../../ai_habit_setup/presentation/ai_habit_setup_sheet.dart';
import '../data/habit_storage.dart';
import '../data/notification_service.dart';
import '../domain/date_key.dart';
import '../domain/habit.dart';
import '../domain/sample_habits.dart';
import 'add_habit_sheet.dart';
import 'habit_details_screen.dart';

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

  void _setHabitStatus(String id, HabitCompletionStatus status) {
    setState(() {
      final index = _habits.indexWhere((h) => h.id == id);
      _habits[index] = _habits[index].setCompletionStatus(todayKey(), status);
    });
    _storage.saveHabits(_habits);
  }

  Future<void> _pickStatus(Habit habit) async {
    if (!mounted) return;
    final result = await showModalBottomSheet<HabitCompletionStatus>(
      context: context,
      builder: (_) => _MinVersionPickerSheet(habit: habit),
    );
    if (result != null && mounted) _setHabitStatus(habit.id, result);
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
    // Flush in-memory state so the details screen can load and save it.
    await _storage.saveHabits(_habits);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => HabitDetailsScreen(
          habit: habit,
          notificationService: _notifications,
        ),
      ),
    );
    if (!mounted) return;
    await _silentReload();
  }

  Future<void> _silentReload() async {
    final habits = await _storage.loadHabits();
    if (!mounted) return;
    setState(() => _habits = habits ?? _habits);
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

    final today = DateTime.now();
    final todayStr = todayKey();
    final scheduledToday = _habits
        .where((h) => h.isActive && h.isScheduledFor(today))
        .toList();
    final fullCount = scheduledToday
        .where(
          (h) => h.completionStatusFor(todayStr) == HabitCompletionStatus.full,
        )
        .length;
    final minimumCount = scheduledToday
        .where(
          (h) =>
              h.completionStatusFor(todayStr) == HabitCompletionStatus.minimum,
        )
        .length;

    return Scaffold(
      appBar: AppBar(title: const Text('Today')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(_formatToday(), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          _ProgressCard(
            fullCount: fullCount,
            minimumCount: minimumCount,
            totalCount: scheduledToday.length,
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
          if (_habits.isNotEmpty && scheduledToday.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Center(
                child: Text(
                  'No habits scheduled for today',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          for (final habit in scheduledToday)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _HabitCard(
                habit: habit,
                onToggle: habit.hasMinimumVersion
                    ? () => _pickStatus(habit)
                    : () => _setHabitStatus(
                        habit.id,
                        habit.completionStatusFor(todayStr) ==
                                HabitCompletionStatus.full
                            ? HabitCompletionStatus.none
                            : HabitCompletionStatus.full,
                      ),
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
  final int fullCount;
  final int minimumCount;
  final int totalCount;

  const _ProgressCard({
    required this.fullCount,
    required this.minimumCount,
    required this.totalCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final score = totalCount == 0
        ? 0.0
        : (fullCount + minimumCount * 0.5) / totalCount;
    final percentage = (score * 100).round();
    final remaining = totalCount - fullCount - minimumCount;

    final parts = <String>['$fullCount full'];
    if (minimumCount > 0) parts.add('$minimumCount minimum');
    if (remaining > 0) parts.add('$remaining remaining');
    final label = totalCount == 0 ? 'No habits today' : parts.join(' · ');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Today's progress", style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: score),
            const SizedBox(height: 8),
            Text(label, style: theme.textTheme.bodyMedium),
            if (score > 0) ...[
              const SizedBox(height: 2),
              Text(
                '$percentage% progress score',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
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
    final status = habit.completionStatusFor(todayKey());

    final icon = switch (status) {
      HabitCompletionStatus.full => Icons.check_circle,
      HabitCompletionStatus.minimum => Icons.adjust,
      HabitCompletionStatus.none => Icons.radio_button_unchecked,
    };
    final iconColor = switch (status) {
      HabitCompletionStatus.full => theme.colorScheme.primary,
      HabitCompletionStatus.minimum => theme.colorScheme.tertiary,
      HabitCompletionStatus.none => null,
    };
    final subtitle = status == HabitCompletionStatus.minimum
        ? '${habit.scheduledTime} · Minimum done'
        : habit.scheduledTime;

    return Card(
      child: ListTile(
        onTap: onTap,
        leading: Icon(habit.icon, color: theme.colorScheme.primary),
        title: Text(habit.title),
        subtitle: Text(subtitle),
        trailing: IconButton(
          icon: Icon(icon, color: iconColor),
          onPressed: onToggle,
        ),
      ),
    );
  }
}

class _MinVersionPickerSheet extends StatelessWidget {
  final Habit habit;

  const _MinVersionPickerSheet({required this.habit});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(habit.title, style: theme.textTheme.titleMedium),
          ),
          ListTile(
            leading: const Icon(Icons.check_circle_outline),
            title: const Text('Complete fully'),
            onTap: () => Navigator.of(context).pop(HabitCompletionStatus.full),
          ),
          ListTile(
            leading: const Icon(Icons.adjust),
            title: const Text('Minimum done'),
            subtitle: Text(habit.minimumVersion ?? ''),
            onTap: () =>
                Navigator.of(context).pop(HabitCompletionStatus.minimum),
          ),
          ListTile(
            leading: const Icon(Icons.radio_button_unchecked),
            title: const Text('Not completed'),
            onTap: () => Navigator.of(context).pop(HabitCompletionStatus.none),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
