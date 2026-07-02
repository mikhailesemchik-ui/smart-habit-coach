import 'package:flutter/material.dart';

import '../../home/domain/habit.dart';
import '../domain/adaptive_suggestion.dart';
import '../domain/adaptive_suggestion_copy.dart';

/// Compact Weekly Review card presenting one locally-detected Adaptive
/// Coach suggestion. Purely deterministic copy — never claims AI produced
/// the recommendation.
class AdaptiveCoachCard extends StatelessWidget {
  final AdaptiveHabitSuggestion suggestion;
  final Habit habit;
  final VoidCallback onKeep;
  final VoidCallback onAdjust;

  /// Non-null only when a safe, fully-specified direct apply is available
  /// (Phase 3: reduceQuantitativeTarget with a proposed target value).
  final VoidCallback? onApply;

  const AdaptiveCoachCard({
    super.key,
    required this.suggestion,
    required this.habit,
    required this.onKeep,
    required this.onAdjust,
    this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final copy = buildAdaptiveSuggestionCopy(suggestion, habit);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Adaptive Coach', style: theme.textTheme.titleMedium),
            const SizedBox(height: 2),
            Text(
              'Based on your recent habit history',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 12),
            Text(copy.title, style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(copy.body, style: theme.textTheme.bodyMedium),
            if (copy.suggestedTargetLine != null) ...[
              const SizedBox(height: 6),
              Text(
                copy.suggestedTargetLine!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 12),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              spacing: 8,
              children: [
                TextButton(
                  onPressed: onKeep,
                  child: const Text('Keep current plan'),
                ),
                if (onApply != null)
                  OutlinedButton(
                    onPressed: onAdjust,
                    child: const Text('Adjust manually'),
                  )
                else
                  FilledButton(
                    onPressed: onAdjust,
                    child: const Text('Adjust manually'),
                  ),
                if (onApply != null)
                  FilledButton(
                    onPressed: onApply,
                    child: const Text('Apply suggestion'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
