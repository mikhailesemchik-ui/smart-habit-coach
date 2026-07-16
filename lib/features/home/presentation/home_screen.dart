import 'package:flutter/material.dart';

import '../../../app/theme/app_radii.dart';
import '../../../app/theme/app_spacing.dart';
import '../../ai_habit_setup/presentation/ai_habit_setup_sheet.dart';
import '../data/habit_storage.dart';
import '../data/notification_service.dart';
import '../domain/date_key.dart';
import '../domain/habit.dart';
import '../domain/sample_habits.dart';
import 'add_habit_sheet.dart';
import 'habit_details_screen.dart';
import 'note_sheet.dart';
import 'partial_reason_sheet.dart';
import 'progress_entry_sheet.dart';
import 'skip_reason_sheet.dart';
import 'undo_snackbar.dart';

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

  // Session-only undo for the last state-changing action.
  Habit? _undoPrev;
  int? _undoHabitIndex;
  // Incremented on every new undo opportunity so stale .closed callbacks
  // from the previous SnackBar cannot clear a newer action's undo state.
  int _undoToken = 0;

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

  // ── Undo ─────────────────────────────────────────────────────────────────

  void _showUndoSnackBar(String message, Habit prev, int index) {
    _undoPrev = prev;
    _undoHabitIndex = index;
    if (!mounted) return;
    _undoToken++;
    final token = _undoToken;
    showUndoSnackBar(
      context,
      message: message,
      onUndo: _undo,
      duration: const Duration(seconds: 4),
    ).closed.then((_) {
      if (!mounted) return;
      if (token == _undoToken) {
        setState(() {
          _undoPrev = null;
          _undoHabitIndex = null;
        });
      }
    });
  }

  Future<void> _undo() async {
    final prev = _undoPrev;
    final idx = _undoHabitIndex;
    _undoPrev = null;
    _undoHabitIndex = null;
    if (prev == null || idx == null || idx < 0 || idx >= _habits.length) {
      return;
    }
    setState(() => _habits[idx] = prev);
    // Undo is its own mutation — upsertHabit stamps a new, later updatedAt.
    final stamped = await _storage.upsertHabit(prev);
    _reconcileHabit(stamped);
  }

  // Reconciles a single stamped/persisted habit back into `_habits` after
  // its centralized write completes, so in-memory state never drifts from
  // what was actually persisted (createdAt/updatedAt in particular). Looks
  // the record up by id rather than trusting a captured index, since other
  // mutations may have completed in the meantime.
  void _reconcileHabit(Habit stamped) {
    if (!mounted) return;
    final index = _habits.indexWhere((h) => h.id == stamped.id);
    if (index == -1) return;
    setState(() => _habits[index] = stamped);
  }

  // ── Habit mutations ───────────────────────────────────────────────────────

  Future<void> _setHabitStatus(String id, HabitCompletionStatus status) async {
    final index = _habits.indexWhere((h) => h.id == id);
    if (index == -1) return;
    final prev = _habits[index];
    final mutated = _habits[index].setCompletionStatus(todayKey(), status);
    setState(() => _habits[index] = mutated);
    _showUndoSnackBar('Habit updated', prev, index);
    final stamped = await _storage.upsertHabit(mutated);
    _reconcileHabit(stamped);
  }

  Future<void> _pickStatus(Habit habit) async {
    if (!mounted) return;
    final result = await showModalBottomSheet<HabitCompletionStatus>(
      context: context,
      builder: (_) => _MinVersionPickerSheet(habit: habit),
    );
    if (result == null || !mounted) return;
    final index = _habits.indexWhere((h) => h.id == habit.id);
    if (index == -1) return;
    final prev = _habits[index];
    final mutated = _habits[index].setCompletionStatus(todayKey(), result);
    setState(() => _habits[index] = mutated);
    _showUndoSnackBar('Habit updated', prev, index);
    final stamped = await _storage.upsertHabit(mutated);
    _reconcileHabit(stamped);
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
    final index = _habits.indexWhere((h) => h.id == habit.id);
    if (index == -1) return;
    final prev = _habits[index];
    final mutated = _habits[index].setSkipReason(
      today,
      result.reason,
      note: result.note,
    );
    setState(() => _habits[index] = mutated);
    _showUndoSnackBar('Habit updated', prev, index);
    final stamped = await _storage.upsertHabit(mutated);
    _reconcileHabit(stamped);
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
    final index = _habits.indexWhere((h) => h.id == habit.id);
    if (index == -1) return;
    final prev = _habits[index];
    final mutated = _habits[index].setProgress(today, result);
    setState(() => _habits[index] = mutated);
    _showUndoSnackBar(
      result == 0 ? 'Progress reset' : 'Habit updated',
      prev,
      index,
    );
    final stamped = await _storage.upsertHabit(mutated);
    _reconcileHabit(stamped);
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
    final index = _habits.indexWhere((h) => h.id == habit.id);
    if (index == -1) return;
    final prev = _habits[index];
    final mutated = _habits[index].setPartialReason(
      today,
      result.reason,
      note: result.note,
    );
    setState(() => _habits[index] = mutated);
    _showUndoSnackBar('Habit updated', prev, index);
    final stamped = await _storage.upsertHabit(mutated);
    _reconcileHabit(stamped);
  }

  Future<void> _editNote(Habit habit) async {
    if (!mounted) return;
    final today = DateTime.now();
    final result = await showNoteSheet(
      context: context,
      habit: habit,
      date: today,
    );
    if (result == null || !mounted) return;
    final index = _habits.indexWhere((h) => h.id == habit.id);
    if (index == -1) return;
    final prev = _habits[index];
    final mutated = _habits[index].setNote(
      today,
      result.isEmpty ? null : result,
    );
    setState(() => _habits[index] = mutated);
    _showUndoSnackBar('Note saved', prev, index);
    final stamped = await _storage.upsertHabit(mutated);
    _reconcileHabit(stamped);
  }

  Future<void> _addHabit(Habit habit) async {
    setState(() => _habits.add(habit));
    final stamped = await _storage.upsertHabit(habit);
    _reconcileHabit(stamped);
    await _notifications.scheduleHabitReminder(stamped);
  }

  Future<void> _openAddHabitSheet() async {
    final newHabit = await showModalBottomSheet<Habit>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AddHabitSheet(),
    );

    if (newHabit != null) {
      await _addHabit(newHabit);
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
        backgroundColor: Colors.transparent,
        builder: (_) => AddHabitSheet(initialHabit: result.habit),
      );
      if (edited == null) return;
      await _addHabit(edited);
    } else {
      await _addHabit(result.habit);
    }
  }

  Future<void> _openHabitDetails(Habit habit) async {
    // Ensures every *other* currently-displayed habit is safely persisted
    // before this one might get deleted in HabitDetailsScreen. Deleting
    // `habit` itself is always safe (tombstoneHabit upserts-then-tombstones
    // it regardless of prior persistence), but its siblings could still be
    // in-memory-only sample habits nobody has touched yet — without this,
    // once raw storage stops being empty (from the delete), loadHabits()
    // would only return the one now-tombstoned record, and every
    // never-individually-persisted sibling would appear to vanish.
    await _storage.ensurePersisted(_habits);
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
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

    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            96,
          ),
          children: [
            Text(
              'Today',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              _formatToday(),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            _ProgressCard(
              completeCount: completeCount,
              partialCount: partialCount,
              totalCount: scheduledToday.length,
              score: progressScore,
            ),
            const SizedBox(height: AppSpacing.md),
            _CreateWithAiCta(onTap: _openAiHabitSetup),
            const SizedBox(height: AppSpacing.lg),
            if (scheduledToday.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Text(
                  "Today's habits",
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (_habits.isNotEmpty && scheduledToday.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Center(
                  child: Text(
                    'No habits scheduled for today',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            for (final habit in scheduledToday)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
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
                  onNote: () => _editNote(habit),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddHabitSheet,
        elevation: 0.5,
        highlightElevation: 1,
        child: const Icon(Icons.add, size: 20),
      ),
    );
  }
}

class _CreateWithAiCta extends StatelessWidget {
  final VoidCallback onTap;

  const _CreateWithAiCta({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Material(
      color: cs.primaryContainer,
      borderRadius: AppRadii.largeRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.largeRadius,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Icon(Icons.auto_awesome, size: 20, color: cs.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Create with AI',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(Icons.arrow_forward_ios, size: 14, color: cs.primary),
            ],
          ),
        ),
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

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: AppRadii.largeRadius,
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          _AnimatedProgressRing(value: score),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Today's progress",
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
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
        ],
      ),
    );
  }
}

/// Small circular progress ring with a centered percentage label. Shows
/// [value] immediately on first build (no animation on mount/reload), and
/// smoothly animates between values only when [value] actually changes —
/// driven by a manually-managed [AnimationController] rather than
/// [TweenAnimationBuilder], since the latter restarts its internal ticker
/// on every rebuild (each build creates a new, non-equal Tween instance),
/// not just on real value changes.
class _AnimatedProgressRing extends StatefulWidget {
  final double value;

  const _AnimatedProgressRing({required this.value});

  @override
  State<_AnimatedProgressRing> createState() => _AnimatedProgressRingState();
}

class _AnimatedProgressRingState extends State<_AnimatedProgressRing>
    with TickerProviderStateMixin {
  late double _displayedValue = widget.value;
  AnimationController? _controller;

  @override
  void didUpdateWidget(covariant _AnimatedProgressRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _animateTo(widget.value);
    }
  }

  void _animateTo(double target) {
    final from = _displayedValue;
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    final curved = CurvedAnimation(parent: controller, curve: Curves.easeOut);
    final tween = Tween<double>(begin: from, end: target);
    controller.addListener(() {
      if (!mounted) return;
      setState(() => _displayedValue = tween.evaluate(curved));
    });
    _controller?.dispose();
    _controller = controller;
    // Deferred to the next frame so this ticker's start doesn't coincide
    // with the same frame as any other animation triggered by the same
    // user action (e.g. a SnackBar's own entrance animation) — keeping
    // this purely-decorative ring animation from perturbing unrelated
    // frame-timing-sensitive behavior elsewhere on the screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _controller == controller) controller.forward();
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percentage = (_displayedValue * 100).round();

    return SizedBox(
      width: 44,
      height: 40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 44,
            height: 40,
            child: CircularProgressIndicator(
              value: _displayedValue,
              strokeWidth: 5,
              backgroundColor: theme.colorScheme.surface,
              color: theme.colorScheme.primary,
            ),
          ),
          Text(
            '$percentage%',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
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
  final VoidCallback onNote;

  const _HabitCard({
    required this.habit,
    required this.onToggle,
    required this.onTap,
    required this.onSkipReason,
    required this.onPartialReason,
    required this.onNote,
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
    final today = DateTime.now();
    final status = habit.completionStatusFor(todayKey());
    final note = habit.noteFor(today);

    final icon = switch (status) {
      HabitCompletionStatus.full => Icons.circle,
      HabitCompletionStatus.minimum => Icons.adjust,
      HabitCompletionStatus.none => Icons.radio_button_unchecked,
    };
    final iconColor = switch (status) {
      HabitCompletionStatus.full => theme.colorScheme.primary,
      HabitCompletionStatus.minimum => theme.colorScheme.tertiary,
      HabitCompletionStatus.none => theme.colorScheme.outline,
    };
    final reason = habit.skipReasonFor(today);
    final reasonLabel = reason == null ? null : habitSkipReasonLabel(reason);
    final statusLine = status == HabitCompletionStatus.minimum
        ? '${habit.scheduledTime} · Minimum done'
        : reasonLabel == null
        ? habit.scheduledTime
        : '${habit.scheduledTime} · Missed · $reasonLabel';

    return _HabitCardShell(
      onTap: onTap,
      leading: _HabitIconBubble(icon: habit.icon),
      title: habit.title,
      statusLine: statusLine,
      note: note,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PopupMenuButton<String>(
            tooltip: 'Habit actions',
            icon: const Icon(Icons.more_vert),
            color: theme.colorScheme.surfaceContainerHigh,
            surfaceTintColor: theme.colorScheme.surfaceTint,
            elevation: 10,
            shadowColor: theme.colorScheme.shadow.withValues(alpha: 0.28),
            shape: RoundedRectangleBorder(
              borderRadius: AppRadii.mediumRadius,
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            position: PopupMenuPosition.under,
            constraints: const BoxConstraints(minWidth: 164),
            onSelected: (value) {
              if (value == 'skip') onSkipReason();
              if (value == 'note') onNote();
            },
            itemBuilder: (_) => [
              if (status == HabitCompletionStatus.none)
                const PopupMenuItem(
                  value: 'skip',
                  height: 40,
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  child: _MenuActionRow(
                    icon: Icons.help_outline,
                    label: 'Why was it missed?',
                  ),
                ),
              PopupMenuItem(
                value: 'note',
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: _MenuActionRow(
                  icon: Icons.note_alt_outlined,
                  label: note != null ? 'Edit note' : 'Add note',
                ),
              ),
            ],
          ),
          IconButton(
            icon: _StatusDot(
              icon: icon,
              color: iconColor,
              ringed: status != HabitCompletionStatus.none,
            ),
            onPressed: onToggle,
          ),
        ],
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
    final note = habit.noteFor(today);

    final progressText = target > 0
        ? '${habitProgressLabel(progress)} / ${habitProgressLabel(target)}'
              '${unit.isNotEmpty ? " $unit" : ""}'
        : habitProgressLabel(progress);

    final statusLine = skipLabel != null && progress == 0
        ? '${habit.scheduledTime} · Missed · $skipLabel'
        : isComplete
        ? '${habit.scheduledTime} · $progressText'
        : isPartial && partialLabel != null
        ? '${habit.scheduledTime} · $progressText · Partial · $partialLabel'
        : isPartial
        ? '${habit.scheduledTime} · $progressText'
        : habit.scheduledTime;

    return _HabitCardShell(
      onTap: onTap,
      leading: _HabitIconBubble(icon: habit.icon, muted: !isComplete),
      title: habit.title,
      statusLine: statusLine,
      note: note,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PopupMenuButton<String>(
            tooltip: 'Habit actions',
            icon: const Icon(Icons.more_vert),
            color: theme.colorScheme.surfaceContainerHigh,
            surfaceTintColor: theme.colorScheme.surfaceTint,
            elevation: 10,
            shadowColor: theme.colorScheme.shadow.withValues(alpha: 0.28),
            shape: RoundedRectangleBorder(
              borderRadius: AppRadii.mediumRadius,
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            position: PopupMenuPosition.under,
            constraints: const BoxConstraints(minWidth: 188),
            onSelected: (value) {
              if (value == 'skip') onSkipReason();
              if (value == 'partial') onPartialReason();
              if (value == 'note') onNote();
            },
            itemBuilder: (_) => [
              if (progress == 0 && !isComplete)
                const PopupMenuItem(
                  value: 'skip',
                  height: 40,
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  child: _MenuActionRow(
                    icon: Icons.help_outline,
                    label: 'Why was it missed?',
                  ),
                ),
              if (isPartial)
                const PopupMenuItem(
                  value: 'partial',
                  height: 40,
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  child: _MenuActionRow(
                    icon: Icons.flag_outlined,
                    label: "Why wasn't the target reached?",
                  ),
                ),
              PopupMenuItem(
                value: 'note',
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: _MenuActionRow(
                  icon: Icons.note_alt_outlined,
                  label: note != null ? 'Edit note' : 'Add note',
                ),
              ),
            ],
          ),
          IconButton(
            tooltip: isComplete ? 'Update progress' : 'Log progress',
            icon: _StatusDot(
              icon: isComplete ? Icons.circle : Icons.add_circle_outline,
              color: isComplete ? cs.primary : cs.outline,
              ringed: isComplete,
            ),
            onPressed: onToggle,
          ),
        ],
      ),
      footer: Padding(
        padding: const EdgeInsets.only(
          top: AppSpacing.sm,
          left: 42,
          right: AppSpacing.xs,
        ),
        child: ClipRRect(
          borderRadius: AppRadii.pillRadius,
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 5,
            backgroundColor: cs.surfaceContainerHighest,
            color: cs.primary.withValues(alpha: 0.55),
          ),
        ),
      ),
    );
  }
}

class _MenuActionRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MenuActionRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}

/// Shared rounded-card shell for both binary and quantitative habit cards —
/// keeps the same title/status/note/trailing-actions structure and text so
/// existing behavior and widget finders (icons, tooltips, popup menu items)
/// are unaffected by the visual restyle.
class _HabitCardShell extends StatelessWidget {
  final VoidCallback onTap;
  final Widget leading;
  final String title;
  final String statusLine;
  final String? note;
  final Widget trailing;
  final Widget? footer;

  const _HabitCardShell({
    required this.onTap,
    required this.leading,
    required this.title,
    required this.statusLine,
    required this.note,
    required this.trailing,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: AppRadii.largeRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.largeRadius,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  leading,
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          statusLine,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (note != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              '"$note"',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontStyle: FontStyle.italic,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  trailing,
                ],
              ),
              ?footer,
            ],
          ),
        ),
      ),
    );
  }
}

/// Unified trailing status control: wraps the existing state icon (kept
/// unchanged so existing `find.byIcon(...)` finders keep working) in a
/// fixed-size circle, adding a subtle outer ring for "positive" states
/// (completed / minimum-done) so a filled dot reads as an intentional
/// status control rather than a flat mark. Not-completed states get no
/// ring, just the plain icon, keeping the same overall footprint.
class _StatusDot extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final bool ringed;

  const _StatusDot({
    required this.icon,
    required this.color,
    this.ringed = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: ringed
            ? Border.all(color: color!.withValues(alpha: 0.3), width: 1.5)
            : null,
      ),
      child: Icon(icon, size: 18, color: color),
    );
  }
}

/// Small rounded icon bubble used as the leading element of a habit card.
class _HabitIconBubble extends StatelessWidget {
  final IconData icon;
  final bool muted;

  const _HabitIconBubble({required this.icon, this.muted = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: muted ? cs.surfaceContainerHighest : cs.primaryContainer,
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        size: 17,
        color: muted ? cs.onSurfaceVariant : cs.primary,
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
