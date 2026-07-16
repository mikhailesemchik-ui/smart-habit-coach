import 'package:flutter/material.dart';

import '../../../app/theme/app_radii.dart';
import '../../../app/theme/app_spacing.dart';
import '../data/habit_storage.dart';
import '../data/notification_service.dart';
import '../domain/habit.dart';
import 'habit_details_screen.dart';

class ArchivedHabitsScreen extends StatefulWidget {
  final NotificationService? notificationService;

  const ArchivedHabitsScreen({super.key, this.notificationService});

  @override
  State<ArchivedHabitsScreen> createState() => _ArchivedHabitsScreenState();
}

class _ArchivedHabitsScreenState extends State<ArchivedHabitsScreen> {
  final HabitStorage _storage = HabitStorage();
  late final NotificationService _notifications =
      widget.notificationService ?? NotificationService();
  List<Habit> _archived = [];
  bool _isLoading = true;

  /// Habit ids with a restore/delete operation currently in flight —
  /// guards against a duplicate tap firing a second storage write before
  /// the first one (and the resulting list reload) completes.
  final Set<String> _pendingIds = {};

  @override
  void initState() {
    super.initState();
    _loadArchived();
  }

  Future<void> _loadArchived() async {
    final all = await _storage.loadHabits();
    if (!mounted) return;
    setState(() {
      _archived = (all ?? [])
          .where((h) => h.status == HabitStatus.archived)
          .toList();
      _isLoading = false;
    });
  }

  Future<void> _openDetails(Habit habit) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => HabitDetailsScreen(
          habit: habit,
          notificationService: widget.notificationService,
        ),
      ),
    );
    if (!mounted) return;
    await _loadArchived();
  }

  Future<void> _restore(Habit habit) async {
    if (!_pendingIds.add(habit.id)) return;
    setState(() {});
    try {
      final restored = habit.asActive();
      // Centralized mutation path: storage stamps updatedAt and marks the
      // habit dirty for sync — this screen never touches either directly.
      await _storage.upsertHabit(restored);
      await _notifications.scheduleHabitReminder(restored);
      if (!mounted) return;
      await _loadArchived();
    } finally {
      _pendingIds.remove(habit.id);
    }
  }

  Future<void> _confirmDelete(Habit habit) async {
    if (_pendingIds.contains(habit.id)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete habit'),
        content: Text('Delete "${habit.title}"? This cannot be undone.'),
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
    if (!_pendingIds.add(habit.id)) return;
    setState(() {});
    try {
      // Tombstone delete: the storage layer stamps deletedAt/updatedAt
      // from a single Clock reading, keeps the record in raw storage, and
      // marks it dirty. The habit is never physically removed.
      await _storage.tombstoneHabit(habit);
      await _notifications.cancelHabitReminder(habit.id);
      if (!mounted) return;
      await _loadArchived();
    } finally {
      _pendingIds.remove(habit.id);
    }
  }

  // Header scrolls away with the rest of the page — it is deliberately NOT
  // in Scaffold.appBar, which Flutter always pins above the body regardless
  // of the body's own scrolling.
  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        const BackButton(),
        const SizedBox(width: AppSpacing.xs),
        Text(
          'Archived habits',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // `bottom: false`: the gesture-bar inset is folded into the ListView's
    // own padding below instead, so it scrolls away with the rest of the
    // page rather than sitting as a fixed panel underneath it.
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final padding = EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset);

    if (_isLoading) {
      return Scaffold(
        body: SafeArea(
          bottom: false,
          child: ListView(
            padding: padding,
            children: [
              _buildHeader(context),
              const SizedBox(height: 24),
              const Center(child: CircularProgressIndicator()),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: padding,
          children: [
            _buildHeader(context),
            const SizedBox(height: AppSpacing.lg),
            if (_archived.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('No archived habits')),
              )
            else
              for (final habit in _archived) ...[
                _ArchivedHabitTile(
                  habit: habit,
                  isBusy: _pendingIds.contains(habit.id),
                  onTap: () => _openDetails(habit),
                  onRestore: () => _restore(habit),
                  onDelete: () => _confirmDelete(habit),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
          ],
        ),
      ),
    );
  }
}

class _ArchivedHabitTile extends StatelessWidget {
  final Habit habit;
  final bool isBusy;
  final VoidCallback onTap;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  const _ArchivedHabitTile({
    required this.habit,
    required this.isBusy,
    required this.onTap,
    required this.onRestore,
    required this.onDelete,
  });

  String _repeatLabel() {
    const weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    if (habit.weekdays.length == 7) return 'Every day';
    return habit.weekdays.map((d) => weekdayLabels[d - 1]).join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: onTap,
              borderRadius: AppRadii.mediumRadius,
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      habit.icon,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          habit.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${habit.scheduledTime} · ${_repeatLabel()}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: AppRadii.pillRadius,
                    ),
                    child: Text(
                      'Archived',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Divider(height: 1),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Semantics(
                  label: 'Restore ${habit.title}',
                  button: true,
                  enabled: !isBusy,
                  child: TextButton.icon(
                    onPressed: isBusy ? null : onRestore,
                    icon: const Icon(Icons.unarchive_outlined, size: 18),
                    label: const Text('Restore'),
                  ),
                ),
                Semantics(
                  label: 'Permanently delete ${habit.title}',
                  button: true,
                  enabled: !isBusy,
                  child: TextButton.icon(
                    onPressed: isBusy ? null : onDelete,
                    icon: Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: theme.colorScheme.error,
                    ),
                    label: Text(
                      'Delete',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
