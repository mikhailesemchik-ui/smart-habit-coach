import 'package:flutter/material.dart';

import '../../ai_habit_setup/presentation/ai_habit_setup_sheet.dart';
import '../data/habit_storage.dart';
import '../data/notification_service.dart';
import '../domain/date_key.dart';
import '../domain/habit.dart';
import '../domain/sample_habits.dart';
import 'add_habit_sheet.dart';
import 'habit_details_screen.dart';
import 'partial_reason_sheet.dart';
import 'progress_entry_sheet.dart';
import 'skip_reason_sheet.dart';

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

  Future<void> _pickSkipReason(Habit habit) async {
    if (!mounted) return;
    final today = DateTime.now();
    final result = await showSkipReasonSheet(
      context: context,
      habit: habit,
      date: today,
    );
    if (result == null || !mounted) return;
    setState(() {
      final index = _habits.indexWhere((h) => h.id == habit.id);
      _habits[index] = _habits[index].setSkipReason(
        today,
        result.reason,
        note: result.note,
      );
    });
    _storage.saveHabits(_habits);
  }

  Future<void> _logProgress(Habit habit) async {
    if (!mounted) return;
    final today = DateTime.now();
    final result = await showProgressEntrySheet(
      context: context,
      habit: habit,
      date: today,
    );
    if (result == null || !mounted) return;
    setState(() {
      final index = _habits.indexWhere((h) => h.id == habit.id);
      _habits[index] = _habits[index].setProgress(today, result);
    });
    _storage.saveHabits(_habits);
  }

  Future<void> _pickPartialReason(Habit habit) async {
    if (!mounted) return;
    final today = DateTime.now();
    final result = await showPartialReasonSheet(
      context: context,
      habit: habit,
      date: today,
    );
    if (result == null || !mounted) return;
    setState(() {
      final index = _habits.indexWhere((h) => h.id == habit.id);
      _habits[index] = _habits[index].setPartialReason(
        today,
        result.reason,
        note: result.note,
      );
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

    double scoreFor(Habit h) {
      if (h.isQuantitative) return h.progressRatioFor(today);
      return switch (h.completionStatusFor(todayStr)) {
        HabitCompletionStatus.full => 1.0,
        HabitCompletionStatus.minimum => 0.5,
        HabitCompletionStatus.none => 0.0,
      };
    }

    final completeCount = scheduledToday.where((h) {
      if (h.isQuantitative) return h.isTargetReached(today);
      return h.completionStatusFor(todayStr) == HabitCompletionStatus.full;
    }).length;

    final partialCount = scheduledToday.where((h) {
      if (h.isQuantitative) return h.hasPartialProgressOn(todayStr);
      return h.completionStatusFor(todayStr) == HabitCompletionStatus.minimum;
    }).length;

    final totalScore = scheduledToday.fold(0.0, (sum, h) => sum + scoreFor(h));
    final progressScore = scheduledToday.isEmpty
        ? 0.0
        : totalScore / scheduledToday.length;

    return Scaffold(
      appBar: AppBar(title: const Text('Today')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(_formatToday(), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          _ProgressCard(
            completeCount: completeCount,
            partialCount: partialCount,
            totalCount: scheduledToday.length,
            score: progressScore,
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
                onToggle: habit.isQuantitative
                    ? () => _logProgress(habit)
                    : habit.hasMinimumVersion
                    ? () => _pickStatus(habit)
                    : () => _setHabitStatus(
                        habit.id,
                        habit.completionStatusFor(todayStr) ==
                                HabitCompletionStatus.full
                            ? HabitCompletionStatus.none
                            : HabitCompletionStatus.full,
                      ),
                onTap: () => _openHabitDetails(habit),
                onSkipReason: () => _pickSkipReason(habit),
                onPartialReason: () => _pickPartialReason(habit),
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
  final int completeCount;
  final int partialCount;
  final int totalCount;
  final double score;

  const _ProgressCard({
    required this.completeCount,
    required this.partialCount,
    required this.totalCount,
    required this.score,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percentage = (score * 100).round();
    final remaining = totalCount - completeCount - partialCount;

    final parts = <String>['$completeCount complete'];
    if (partialCount > 0) parts.add('$partialCount partial');
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
  final VoidCallback onSkipReason;
  final VoidCallback onPartialReason;

  const _HabitCard({
    required this.habit,
    required this.onToggle,
    required this.onTap,
    required this.onSkipReason,
    required this.onPartialReason,
  });

  @override
  Widget build(BuildContext context) {
    if (habit.isQuantitative) {
      return _buildQuantitativeCard(context);
    }
    return _buildBinaryCard(context);
  }

  Widget _buildBinaryCard(BuildContext context) {
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
    final reason = habit.skipReasonFor(DateTime.now());
    final reasonLabel = reason == null ? null : habitSkipReasonLabel(reason);
    final subtitle = status == HabitCompletionStatus.minimum
        ? '${habit.scheduledTime} · Minimum done'
        : reasonLabel == null
        ? habit.scheduledTime
        : '${habit.scheduledTime} · Missed · $reasonLabel';

    return Card(
      child: ListTile(
        onTap: onTap,
        leading: Icon(habit.icon, color: theme.colorScheme.primary),
        title: Text(habit.title),
        subtitle: Text(subtitle),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (status == HabitCompletionStatus.none)
              IconButton(
                tooltip: 'Why was it missed?',
                icon: const Icon(Icons.more_horiz),
                onPressed: onSkipReason,
              ),
            IconButton(
              icon: Icon(icon, color: iconColor),
              onPressed: onToggle,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuantitativeCard(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final today = DateTime.now();
    final todayStr = todayKey();
    final progress = habit.progressFor(today);
    final target = habit.targetValue ?? 0;
    final ratio = habit.progressRatioFor(today);
    final unit = habit.unit ?? '';
    final isComplete = habit.isTargetReached(today);
    final isPartial = habit.hasPartialProgressOn(todayStr);
    final skipReason = habit.skipReasonFor(today);
    final skipLabel = skipReason == null
        ? null
        : habitSkipReasonLabel(skipReason);
    final partialReason = habit.partialReasonFor(today);
    final partialLabel = partialReason == null
        ? null
        : habitPartialReasonLabel(partialReason);

    final progressText = target > 0
        ? '${habitProgressLabel(progress)} / ${habitProgressLabel(target)}'
              '${unit.isNotEmpty ? " $unit" : ""}'
        : habitProgressLabel(progress);

    final subtitle = skipLabel != null && progress == 0
        ? '${habit.scheduledTime} · Missed · $skipLabel'
        : isComplete
        ? '${habit.scheduledTime} · $progressText'
        : isPartial && partialLabel != null
        ? '${habit.scheduledTime} · $progressText · Partial · $partialLabel'
        : isPartial
        ? '${habit.scheduledTime} · $progressText'
        : habit.scheduledTime;

    return Card(
      child: Column(
        children: [
          ListTile(
            onTap: onTap,
            leading: Icon(
              habit.icon,
              color: isComplete ? cs.primary : cs.onSurfaceVariant,
            ),
            title: Text(habit.title),
            subtitle: Text(subtitle),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (progress == 0 && !isComplete)
                  IconButton(
                    tooltip: 'Why was it missed?',
                    icon: const Icon(Icons.more_horiz),
                    onPressed: onSkipReason,
                  ),
                if (isPartial)
                  IconButton(
                    tooltip: "Why wasn't the target reached?",
                    icon: const Icon(Icons.more_horiz),
                    onPressed: onPartialReason,
                  ),
                IconButton(
                  tooltip: isComplete ? 'Update progress' : 'Log progress',
                  icon: Icon(
                    isComplete ? Icons.check_circle : Icons.add_circle_outline,
                    color: isComplete ? cs.primary : null,
                  ),
                  onPressed: onToggle,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: LinearProgressIndicator(value: ratio),
          ),
        ],
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
