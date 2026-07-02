import 'package:flutter/material.dart';

import '../data/coach_insights_service.dart';
import '../domain/adaptive_suggestion.dart';
import '../domain/adaptive_suggestion_history_copy.dart';
import '../domain/coach_insights_view.dart';

const _monthAbbrev = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Formats [date] as e.g. "Jul 2, 2026" using local time — never a raw
/// ISO string.
String formatCoachInsightsDate(DateTime date) {
  final local = date.toLocal();
  return '${_monthAbbrev[local.month - 1]} ${local.day}, ${local.year}';
}

String _statusGroupTitle(AdaptiveSuggestionStatus status) {
  switch (status) {
    case AdaptiveSuggestionStatus.pending:
      return 'Pending';
    case AdaptiveSuggestionStatus.applied:
      return 'Applied';
    case AdaptiveSuggestionStatus.adjusted:
      return 'Adjusted';
    case AdaptiveSuggestionStatus.kept:
      return 'Kept';
    case AdaptiveSuggestionStatus.rejected:
      return 'Rejected';
  }
}

Color _statusColor(BuildContext context, AdaptiveSuggestionStatus status) {
  final scheme = Theme.of(context).colorScheme;
  switch (status) {
    case AdaptiveSuggestionStatus.pending:
      return scheme.secondaryContainer;
    case AdaptiveSuggestionStatus.applied:
      return scheme.primaryContainer;
    case AdaptiveSuggestionStatus.adjusted:
      return scheme.secondaryContainer;
    case AdaptiveSuggestionStatus.kept:
      return scheme.surfaceContainerHighest;
    case AdaptiveSuggestionStatus.rejected:
      return scheme.surfaceContainerHighest;
  }
}

/// Read-only history of previous Adaptive Coach suggestions. Never applies,
/// adjusts, keeps, or otherwise mutates a suggestion's status — opening
/// this screen has no side effects on stored data.
class CoachInsightsScreen extends StatefulWidget {
  final CoachInsightsService? service;

  const CoachInsightsScreen({super.key, this.service});

  @override
  State<CoachInsightsScreen> createState() => _CoachInsightsScreenState();
}

class _CoachInsightsScreenState extends State<CoachInsightsScreen> {
  late final CoachInsightsService _service =
      widget.service ?? CoachInsightsService();

  bool _isLoading = true;
  bool _hasError = false;
  List<CoachInsightsGroup> _groups = const [];
  CoachInsightsLoadResult? _result;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    final result = await _service.load();
    if (!mounted) return;
    setState(() {
      _result = result;
      _hasError = result.hasError;
      _groups = groupSuggestionsForInsights(result.suggestions);
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Coach Insights')),
      body: RefreshIndicator(onRefresh: _load, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_hasError) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [_ErrorState(onRetry: _load)],
      );
    }
    if (_groups.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [_EmptyState()],
      );
    }

    final habits = _result!.habits;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Your habit plan adjustments and recent coaching history',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        for (final group in _groups) ...[
          Text(
            _statusGroupTitle(group.status),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          for (final suggestion in group.suggestions) ...[
            _CoachInsightCard(
              suggestion: suggestion,
              habitTitle: resolveHabitDisplayTitle(suggestion, habits),
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _CoachInsightCard extends StatelessWidget {
  final AdaptiveHabitSuggestion suggestion;
  final String habitTitle;

  const _CoachInsightCard({required this.suggestion, required this.habitTitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final evidenceText = buildAdaptiveSuggestionEvidenceText(suggestion);
    final targetLine = adaptiveSuggestionTargetLine(
      suggestion,
      suggestion.originalUnit,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(habitTitle, style: theme.textTheme.titleSmall),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor(context, suggestion.status),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    adaptiveSuggestionStatusLabel(suggestion.status),
                    style: theme.textTheme.labelSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              adaptiveSuggestionTypeLabel(suggestion.type),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              formatCoachInsightsDate(suggestion.createdAt),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 8),
            Text(evidenceText, style: theme.textTheme.bodyMedium),
            if (targetLine != null) ...[
              const SizedBox(height: 4),
              Text(
                targetLine,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('No coach insights yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Adaptive Coach suggestions will appear here after enough '
              'habit history is available.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Keep tracking your habits to build a clearer picture of '
              'what works for you.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;

  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Couldn't load coach insights."),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
