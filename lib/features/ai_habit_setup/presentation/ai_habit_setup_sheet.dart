import 'package:flutter/material.dart';

import '../../home/domain/habit.dart';
import '../../home/presentation/add_habit_sheet.dart';
import '../data/ai_habit_setup_service.dart';
import '../domain/ai_habit_setup_exception.dart';
import '../domain/ai_habit_suggestion_source.dart';
import '../domain/habit_suggestion.dart';

class AiHabitSetupResult {
  final Habit habit;
  final bool openForEditing;

  const AiHabitSetupResult({required this.habit, required this.openForEditing});
}

enum _SuggestionStatus { idle, loading, success, error }

const _unexpectedErrorMessage =
    "Couldn't generate a suggestion right now. Please try again.";

String _formatWeekdays(List<int> weekdays) {
  if (weekdays.length == 7) return 'Every day';
  const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return weekdays.map((d) => labels[d - 1]).join(', ');
}

String _repeatLabel(HabitSuggestion suggestion) {
  if (!suggestion.isResolved) {
    final n = suggestion.requiredDaysPerWeek!;
    return 'Choose $n ${n == 1 ? "day" : "days"}';
  }
  return _formatWeekdays(suggestion.weekdays);
}

class AiHabitSetupSheet extends StatefulWidget {
  final AiHabitSuggestionSource? service;

  const AiHabitSetupSheet({super.key, this.service});

  @override
  State<AiHabitSetupSheet> createState() => _AiHabitSetupSheetState();
}

class _AiHabitSetupSheetState extends State<AiHabitSetupSheet> {
  final _inputController = TextEditingController();
  late final AiHabitSuggestionSource _service =
      widget.service ?? AiHabitSetupService();

  _SuggestionStatus _status = _SuggestionStatus.idle;
  HabitSuggestion? _suggestion;
  String? _errorMessage;

  /// The trimmed prompt that produced the current [_suggestion].
  String? _generatedPrompt;

  /// True while a regeneration (from stale state) is in progress.
  bool _isRegenerating = false;

  /// Error message from the most recent failed regeneration attempt.
  String? _regenerateError;

  bool get _isStale =>
      _status == _SuggestionStatus.success &&
      _suggestion != null &&
      _generatedPrompt != null &&
      _inputController.text.trim() != _generatedPrompt;

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _generatePlan() async {
    if (_status == _SuggestionStatus.loading || _isRegenerating) return;
    FocusScope.of(context).unfocus();

    final wasStale = _isStale;

    if (wasStale) {
      setState(() {
        _isRegenerating = true;
        _regenerateError = null;
      });
    } else {
      setState(() {
        _status = _SuggestionStatus.loading;
        _errorMessage = null;
      });
    }

    final goal = _inputController.text.trim();

    try {
      final suggestion = await _service.generateSuggestion(goal);
      if (!mounted) return;
      setState(() {
        _suggestion = suggestion;
        _status = _SuggestionStatus.success;
        _generatedPrompt = goal;
        _isRegenerating = false;
        _regenerateError = null;
      });
    } on AiHabitSetupException catch (e) {
      if (!mounted) return;
      if (wasStale) {
        setState(() {
          _isRegenerating = false;
          _regenerateError = e.message;
        });
      } else {
        setState(() {
          _errorMessage = e.message;
          _status = _SuggestionStatus.error;
        });
      }
    } catch (_) {
      if (!mounted) return;
      if (wasStale) {
        setState(() {
          _isRegenerating = false;
          _regenerateError = _unexpectedErrorMessage;
        });
      } else {
        setState(() {
          _errorMessage = _unexpectedErrorMessage;
          _status = _SuggestionStatus.error;
        });
      }
    }
  }

  void _accept() {
    final suggestion = _suggestion;
    if (suggestion == null || !suggestion.isResolved || _isStale) return;
    Navigator.of(context).pop(
      AiHabitSetupResult(habit: suggestion.toHabit(), openForEditing: false),
    );
  }

  void _editBeforeSaving() {
    final suggestion = _suggestion;
    if (suggestion == null) return;
    Navigator.of(context).pop(
      AiHabitSetupResult(habit: suggestion.toHabit(), openForEditing: true),
    );
  }

  Future<void> _openDayPicker() async {
    final s = _suggestion;
    if (s == null) return;

    final partialHabit = Habit(
      id: 'ai-unresolved',
      title: s.title,
      scheduledTime: s.scheduledTime,
      icon: s.icon,
      weekdays: s.weekdays,
    );

    final result = await showModalBottomSheet<Habit>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AddHabitSheet(
        initialHabit: partialHabit,
        requiredDaysPerWeek: s.requiredDaysPerWeek,
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _suggestion = s.withWeekdays(result.weekdays);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Create with AI', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _inputController,
              maxLines: 3,
              enabled: _status != _SuggestionStatus.loading && !_isRegenerating,
              onChanged: (_) {
                if (_suggestion != null) setState(() {});
              },
              decoration: const InputDecoration(
                labelText: 'What do you want to improve?',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            _buildBody(),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_status) {
      case _SuggestionStatus.loading:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Center(child: CircularProgressIndicator()),
        );
      case _SuggestionStatus.error:
        return _ErrorView(
          message: _errorMessage ?? _unexpectedErrorMessage,
          onRetry: _generatePlan,
          onCancel: () => Navigator.of(context).pop(),
        );
      case _SuggestionStatus.success:
        return _buildSuccessBody();
      case _SuggestionStatus.idle:
        return OverflowBar(
          alignment: MainAxisAlignment.end,
          spacing: 8,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: _generatePlan,
              child: const Text('Generate plan'),
            ),
          ],
        );
    }
  }

  Widget _buildSuccessBody() {
    final suggestion = _suggestion;
    if (suggestion == null) return const SizedBox.shrink();

    final stale = _isStale;
    final canAdd = !stale && !_isRegenerating && suggestion.isResolved;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Opacity(
          opacity: (stale || _isRegenerating) ? 0.55 : 1.0,
          child: _SuggestionCard(
            suggestion: suggestion,
            repeatLabel: _repeatLabel(suggestion),
          ),
        ),
        if (_isRegenerating)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (_regenerateError != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _regenerateError!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        if (stale && !_isRegenerating)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Generate again to update the suggestion.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        const SizedBox(height: 16),
        OverflowBar(
          alignment: MainAxisAlignment.end,
          spacing: 8,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            if (!_isRegenerating) ...[
              TextButton(
                onPressed: suggestion.isResolved
                    ? _editBeforeSaving
                    : _openDayPicker,
                child: const Text('Edit'),
              ),
              if (stale || _regenerateError != null)
                FilledButton(
                  onPressed: _isRegenerating ? null : _generatePlan,
                  child: const Text('Generate again'),
                )
              else
                FilledButton(
                  onPressed: canAdd ? _accept : null,
                  child: const Text('Add habit'),
                ),
            ],
          ],
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onCancel;

  const _ErrorView({
    required this.message,
    required this.onRetry,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          message,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
        const SizedBox(height: 16),
        OverflowBar(
          alignment: MainAxisAlignment.end,
          spacing: 8,
          children: [
            TextButton(onPressed: onCancel, child: const Text('Cancel')),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ],
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  final HabitSuggestion suggestion;
  final String repeatLabel;

  const _SuggestionCard({required this.suggestion, required this.repeatLabel});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(suggestion.icon, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    suggestion.title,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(suggestion.reason, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            Text(
              'Suggested time: ${suggestion.scheduledTime}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text('Repeat: $repeatLabel', style: theme.textTheme.bodySmall),
            if (suggestion.minimumVersion != null) ...[
              const SizedBox(height: 4),
              Text(
                'Minimum: ${suggestion.minimumVersion}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
