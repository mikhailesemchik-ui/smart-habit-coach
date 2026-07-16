import 'package:flutter/material.dart';

import '../../../app/theme/app_radii.dart';
import '../../../app/theme/app_spacing.dart';
import '../data/habit_storage.dart';
import '../data/notification_service.dart';
import '../domain/date_key.dart';
import '../domain/habit.dart';
import '../domain/habit_stats.dart';
import 'add_habit_sheet.dart';
import 'note_sheet.dart';
import 'partial_reason_sheet.dart';
import 'progress_entry_sheet.dart';
import 'skip_reason_sheet.dart';

const _weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

enum _DateAction { skipReason, note }

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

  /// Saved before a date mutation for session-only undo.
  Habit? _undoHabit;
  int _undoToken = 0;

  @override
  void initState() {
    super.initState();
    _habit = widget.habit;
    _notifications = widget.notificationService ?? NotificationService();
    final now = widget.today ?? DateTime.now();
    _today = DateTime(now.year, now.month, now.day);
    _displayedMonth = DateTime(_today.year, _today.month, 1);
  }

  // ── Undo ───────────────────────────────────────────────────────────────────

  void _showUndoSnackBar(String message) {
    if (!mounted || _undoHabit == null) return;
    _undoToken++;
    final token = _undoToken;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 4),
          action: SnackBarAction(label: 'Undo', onPressed: _undoDateChange),
        ),
      ).closed.then((reason) {
        if (!mounted) return;
        if (reason != SnackBarClosedReason.action && token == _undoToken) {
          setState(() => _undoHabit = null);
        }
      });
  }

  Future<void> _undoDateChange() async {
    final prev = _undoHabit;
    _undoHabit = null;
    if (prev == null) return;
    setState(() => _habit = prev);
    await _persistHabit(prev);
  }

  Future<void> _editNote(DateTime day) async {
    if (!mounted) return;
    final result = await showNoteSheet(
      context: context,
      habit: _habit,
      date: day,
    );
    if (result == null || !mounted) return;
    _undoHabit = _habit;
    final updated = _habit.setNote(day, result.isEmpty ? null : result);
    setState(() => _habit = updated);
    await _persistHabit(updated);
    _showUndoSnackBar('Note saved');
  }

  // ── Habit mutations ─────────────────────────────────────────────────────────

  Future<void> _setDateStatus(
    DateTime day,
    HabitCompletionStatus status,
  ) async {
    if (day.isAfter(_today) || !_habit.isScheduledFor(day)) return;
    _undoHabit = _habit;
    final updated = _habit.setCompletionStatus(dateKey(day), status);
    setState(() => _habit = updated);
    await _persistHabit(updated);
    _showUndoSnackBar('Habit updated');
  }

  Future<void> _setDateSkipReason(DateTime day) async {
    if (day.isAfter(_today) || !_habit.isScheduledFor(day)) return;
    final result = await showSkipReasonSheet(
      context: context,
      habit: _habit,
      date: day,
    );
    if (result == null || !mounted) return;
    _undoHabit = _habit;
    final updated = _habit.setSkipReason(day, result.reason, note: result.note);
    setState(() => _habit = updated);
    await _persistHabit(updated);
    _showUndoSnackBar('Habit updated');
  }

  Future<void> _setPartialReason(DateTime day) async {
    final result = await showPartialReasonSheet(
      context: context,
      habit: _habit,
      date: day,
    );
    if (result == null || !mounted) return;
    _undoHabit = _habit;
    final updated = _habit.setPartialReason(
      day,
      result.reason,
      note: result.note,
    );
    setState(() => _habit = updated);
    await _persistHabit(updated);
    _showUndoSnackBar('Habit updated');
  }

  Future<void> _openDateActions(DateTime day) async {
    if (day.isAfter(_today) || !_habit.isScheduledFor(day)) return;
    if (_habit.isQuantitative) {
      final action = await showModalBottomSheet<String>(
        context: context,
        builder: (_) => _QuantCalendarDateSheet(habit: _habit, day: day),
      );
      if (action == null || !mounted) return;
      if (action == 'note') {
        await _editNote(day);
        return;
      }
      // action == 'progress'
      final result = await showProgressEntrySheet(
        context: context,
        habit: _habit,
        date: day,
      );
      if (result == null || !mounted) return;
      _undoHabit = _habit;
      var updated = _habit.setProgress(day, result);
      setState(() => _habit = updated);
      await _persistHabit(updated);
      _showUndoSnackBar(result == 0 ? 'Progress reset' : 'Habit updated');
      if (!mounted) return;
      if (updated.hasPartialProgressOn(dateKey(day))) {
        await _setPartialReason(day);
      }
      return;
    }
    final result = await showModalBottomSheet<Object>(
      context: context,
      builder: (_) => _DateStatusSheet(habit: _habit, day: day),
    );
    if (result == null || !mounted) return;
    if (result == _DateAction.skipReason) {
      await _setDateSkipReason(day);
    } else if (result == _DateAction.note) {
      await _editNote(day);
    } else if (result is HabitCompletionStatus) {
      await _setDateStatus(day, result);
    }
  }

  // Persists [habit] through the centralized write path and reconciles
  // `_habit` with the actually-stamped/persisted record afterward — the
  // preceding optimistic `setState(() => _habit = habit)` at each call site
  // keeps the UI responsive immediately, this closes the loop so in-memory
  // state never drifts from what storage actually holds (createdAt in
  // particular is only known for certain once the write returns).
  Future<void> _persistHabit(Habit habit) async {
    final stamped = await _storage.upsertHabit(habit);
    if (!mounted || stamped.id != _habit.id) return;
    setState(() => _habit = stamped);
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
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => AddHabitSheet(initialHabit: _habit),
    );
    if (updated == null || !mounted) return;
    setState(() => _habit = updated);
    await _persistHabit(updated);
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
    // Tombstone delete: the habit is never physically removed. The
    // storage layer stamps deletedAt/updatedAt, keeps the record in raw
    // storage, and marks it dirty; normal reads (Home, Progress, Day
    // History, Archived Habits, etc.) hide it from here on.
    await _storage.tombstoneHabit(_habit);
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

  String _statusTextFor(DateTime day) {
    if (_habit.isQuantitative) {
      return _quantitativeStatusText(day);
    }
    final key = dateKey(day);
    return switch (_habit.completionStatusFor(key)) {
      HabitCompletionStatus.full => 'Completed',
      HabitCompletionStatus.minimum => 'Minimum done',
      HabitCompletionStatus.none => _skipReasonTextFor(day) ?? 'Not completed',
    };
  }

  String _quantitativeStatusText(DateTime day) {
    final progress = _habit.progressFor(day);
    final target = _habit.targetValue ?? 0;
    final unit = _habit.unit ?? '';
    if (progress == 0) {
      final reason = _habit.skipReasonFor(day);
      if (reason != null) {
        return 'Missed · ${habitSkipReasonLabel(reason)}';
      }
      return 'Not logged';
    }
    final p = habitProgressLabel(progress);
    final t = habitProgressLabel(target);
    final progressStr = target > 0
        ? '$p / $t${unit.isNotEmpty ? " $unit" : ""}'
        : p;
    if (_habit.isTargetReached(day)) return 'Done · $progressStr';
    final partialReason = _habit.partialReasonFor(day);
    if (partialReason != null) {
      return '$progressStr · Partial · ${habitPartialReasonLabel(partialReason)}';
    }
    return progressStr;
  }

  String? _skipReasonTextFor(DateTime day) {
    final reason = _habit.skipReasonFor(day);
    if (reason == null) return null;
    final note = _habit.skipReasonNoteFor(day);
    final label = habitSkipReasonLabel(reason);
    return note == null ? 'Missed · $label' : 'Missed · $label: $note';
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

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: AppRadii.largeRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _HeroIconBubble(icon: _habit.icon),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  _habit.title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: AppRadii.pillRadius,
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
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: AppRadii.mediumRadius,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _LabelValue(label: 'Reminder', value: _habit.scheduledTime),
                const SizedBox(height: AppSpacing.xs),
                _LabelValue(label: 'Repeat', value: _repeatLabel()),
                if (_habit.isQuantitative && _habit.targetValue != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  _LabelValue(
                    label: 'Target',
                    value:
                        '${habitProgressLabel(_habit.targetValue!)}${_habit.unit != null ? " ${_habit.unit}" : ""}',
                  ),
                ],
                if (_habit.hasMinimumVersion) ...[
                  const SizedBox(height: AppSpacing.xs),
                  _LabelValue(label: 'Minimum', value: _habit.minimumVersion!),
                ],
                const SizedBox(height: AppSpacing.xs),
                _LabelValue(label: 'Today', value: _statusTextFor(_today)),
                if (_habit.noteFor(_today) != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  _LabelValue(
                    label: 'Note',
                    value: '"${_habit.noteFor(_today)}"',
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCard(ThemeData theme) {
    final streak = habitCurrentStreak(_habit, _today);
    final best = habitBestStreak(_habit, _today);
    final mostCommonReason = habitMostCommonSkipReason(_habit, _today);

    if (_habit.isQuantitative) {
      return _buildQuantitativeStatsCard(
        theme,
        streak: streak,
        best: best,
        mostCommonReason: mostCommonReason,
      );
    }

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
                const SizedBox(width: AppSpacing.sm),
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
                const SizedBox(width: AppSpacing.sm),
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
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _StatTile(
                      label: 'Consistency',
                      value: '${(consistencyRate * 100).round()}%',
                    ),
                  ),
                ],
              ),
            ],
            if (mostCommonReason != null) ...[
              const SizedBox(height: 12),
              _StatTile(
                label: 'Most common reason',
                value:
                    '${habitSkipReasonLabel(mostCommonReason.key)} · '
                    '${mostCommonReason.value} '
                    '${mostCommonReason.value == 1 ? 'time' : 'times'}',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildQuantitativeStatsCard(
    ThemeData theme, {
    required int streak,
    required int best,
    required MapEntry<HabitSkipReason, int>? mostCommonReason,
  }) {
    final targetRate = habitQuantitativeTargetRate(_habit, _today);
    final consistencyRate = habitQuantitativeConsistencyRate(_habit, _today);
    final avgLogged = habitQuantitativeAverageLogged(_habit, _today);
    final unit = _habit.unit ?? '';

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
                    label: 'Target streak',
                    value: _pluralDays(streak),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
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
                    label: 'Target rate (30d)',
                    value: '${(targetRate * 100).round()}%',
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _StatTile(
                    label: 'Consistency (30d)',
                    value: '${(consistencyRate * 100).round()}%',
                  ),
                ),
              ],
            ),
            if (avgLogged > 0) ...[
              const SizedBox(height: 12),
              _StatTile(
                label: 'Avg when logged',
                value:
                    '${habitProgressLabel(avgLogged)}'
                    '${unit.isNotEmpty ? " $unit" : ""}',
              ),
            ],
            if (mostCommonReason != null) ...[
              const SizedBox(height: 12),
              _StatTile(
                label: 'Most common reason',
                value:
                    '${habitSkipReasonLabel(mostCommonReason.key)} · '
                    '${mostCommonReason.value} '
                    '${mostCommonReason.value == 1 ? 'time' : 'times'}',
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

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: AppRadii.largeRadius,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Activity', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
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
              final key = dateKey(day);
              final dayStatus = _habit.completionStatusFor(key);
              final isPartial =
                  _habit.isQuantitative && _habit.hasPartialProgressOn(key);

              return _CalendarDayCell(
                day: day,
                isScheduled: isScheduled,
                isCompleted: dayStatus == HabitCompletionStatus.full,
                isMinimum:
                    !_habit.isQuantitative &&
                    dayStatus == HabitCompletionStatus.minimum,
                isPartial: isPartial,
                isToday: isToday,
                isFuture: isFuture,
                onTap: (isFuture || !isScheduled)
                    ? null
                    : () => _openDateActions(day),
              );
            },
          ),
        ],
      ),
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
        const SizedBox(height: AppSpacing.lg),
        Center(
          child: Semantics(
            label: 'Permanently delete ${_habit.title}',
            button: true,
            child: OutlinedButton.icon(
              onPressed: _deleteHabit,
              icon: Icon(
                Icons.delete_outline,
                size: 18,
                color: theme.colorScheme.error,
              ),
              label: Text(
                'Delete habit',
                style: TextStyle(color: theme.colorScheme.error),
              ),
              style: OutlinedButton.styleFrom(side: BorderSide.none),
            ),
          ),
        ),
      ],
    );
  }
}

class _DateStatusSheet extends StatelessWidget {
  final Habit habit;
  final DateTime day;

  const _DateStatusSheet({required this.habit, required this.day});

  @override
  Widget build(BuildContext context) {
    final key = dateKey(day);
    final status = habit.completionStatusFor(key);
    final reason = habit.skipReasonFor(day);
    final reasonText = reason == null ? null : habitSkipReasonLabel(reason);

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                habit.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (reasonText != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('Missed · $reasonText'),
              ),
            ListTile(
              leading: Icon(
                status == HabitCompletionStatus.full
                    ? Icons.check_circle
                    : Icons.check_circle_outline,
              ),
              title: const Text('Complete fully'),
              onTap: () =>
                  Navigator.of(context).pop(HabitCompletionStatus.full),
            ),
            if (habit.hasMinimumVersion)
              ListTile(
                leading: Icon(
                  status == HabitCompletionStatus.minimum
                      ? Icons.adjust
                      : Icons.adjust_outlined,
                ),
                title: const Text('Minimum done'),
                subtitle: Text(habit.minimumVersion ?? ''),
                onTap: () =>
                    Navigator.of(context).pop(HabitCompletionStatus.minimum),
              ),
            ListTile(
              leading: Icon(
                status == HabitCompletionStatus.none
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              title: const Text('Not completed'),
              onTap: () =>
                  Navigator.of(context).pop(HabitCompletionStatus.none),
            ),
            ListTile(
              leading: const Icon(Icons.more_horiz),
              title: const Text('Why was it missed?'),
              onTap: () => Navigator.of(context).pop(_DateAction.skipReason),
            ),
            ListTile(
              leading: const Icon(Icons.notes),
              title: Text(
                habit.noteFor(day) != null ? 'Edit note' : 'Add note',
              ),
              onTap: () => Navigator.of(context).pop(_DateAction.note),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Rounded icon bubble shown in the Habit Details hero card.
class _HeroIconBubble extends StatelessWidget {
  final IconData icon;

  const _HeroIconBubble({required this.icon});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(color: cs.surface, shape: BoxShape.circle),
      child: Icon(icon, color: cs.primary, size: 24),
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
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: AppRadii.mediumRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
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
      ),
    );
  }
}

/// Intermediate action sheet for tapping a quantitative calendar date.
class _QuantCalendarDateSheet extends StatelessWidget {
  final Habit habit;
  final DateTime day;

  const _QuantCalendarDateSheet({required this.habit, required this.day});

  @override
  Widget build(BuildContext context) {
    final note = habit.noteFor(day);
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              habit.title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.add_circle_outline),
            title: const Text('Log progress'),
            onTap: () => Navigator.of(context).pop('progress'),
          ),
          ListTile(
            leading: const Icon(Icons.notes),
            title: Text(note != null ? 'Edit note' : 'Add note'),
            onTap: () => Navigator.of(context).pop('note'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _CalendarDayCell extends StatelessWidget {
  final DateTime day;
  final bool isScheduled;
  final bool isCompleted;
  final bool isMinimum;
  final bool isPartial;
  final bool isToday;
  final bool isFuture;
  final VoidCallback? onTap;

  const _CalendarDayCell({
    required this.day,
    required this.isScheduled,
    required this.isCompleted,
    required this.isMinimum,
    this.isPartial = false,
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
    } else if (isPartial) {
      bg = cs.secondary.withValues(alpha: 0.25);
      textColor = cs.secondary;
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
