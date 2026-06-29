import 'package:flutter/material.dart';

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
  List<Habit> _archived = [];
  bool _isLoading = true;

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
                return _ArchivedHabitTile(
                  habit: habit,
                  onTap: () => _openDetails(habit),
                );
              },
            ),
    );
  }
}

class _ArchivedHabitTile extends StatelessWidget {
  final Habit habit;
  final VoidCallback onTap;

  const _ArchivedHabitTile({required this.habit, required this.onTap});

  String _repeatLabel() {
    const weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    if (habit.weekdays.length == 7) return 'Every day';
    return habit.weekdays.map((d) => weekdayLabels[d - 1]).join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: ListTile(
        onTap: onTap,
        leading: Icon(habit.icon, color: theme.colorScheme.onSurfaceVariant),
        title: Text(habit.title),
        subtitle: Text('${habit.scheduledTime} · ${_repeatLabel()}'),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
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
    );
  }
}
