import 'package:flutter/material.dart';

import '../../../app/theme/app_radii.dart';
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Archived habits')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Archived habits')),
      body: _archived.isEmpty
          ? const Center(child: Text('No archived habits'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _archived.length,
              itemBuilder: (context, index) {
                final habit = _archived[index];
                final isPending = _pendingIds.contains(habit.id);
                return _ArchivedHabitTile(
                  habit: habit,
                  isBusy: isPending,
                  onTap: () => _openDetails(habit),
                  onRestore: () => _restore(habit),
                  onDelete: () => _confirmDelete(habit),
                );
              },
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            onTap: onTap,
            leading: Icon(
              habit.icon,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            title: Text(habit.title),
            subtitle: Text('${habit.scheduledTime} · ${_repeatLabel()}'),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.12,
                ),
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
          ),
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
              const SizedBox(width: 8),
            ],
          ),
        ],
      ),
    );
  }
}
