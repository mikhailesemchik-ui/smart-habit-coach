import 'package:flutter/material.dart';

import '../domain/habit.dart';

enum HabitDetailsAction { edit, delete }

class HabitDetailsSheet extends StatelessWidget {
  final Habit habit;

  const HabitDetailsSheet({super.key, required this.habit});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(habit.icon, color: theme.colorScheme.primary, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(habit.title, style: theme.textTheme.titleLarge),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Scheduled time', style: theme.textTheme.titleSmall),
            Text(habit.scheduledTime, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 16),
            Text('Status', style: theme.textTheme.titleSmall),
            Text(
              habit.isCompletedToday ? 'Completed' : 'Not completed',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () =>
                      Navigator.of(context).pop(HabitDetailsAction.delete),
                  child: const Text('Delete'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () =>
                      Navigator.of(context).pop(HabitDetailsAction.edit),
                  child: const Text('Edit'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
