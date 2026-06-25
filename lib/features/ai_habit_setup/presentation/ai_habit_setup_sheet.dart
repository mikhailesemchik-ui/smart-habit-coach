import 'package:flutter/material.dart';

import '../../home/domain/habit.dart';
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

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _generatePlan() async {
    if (_status == _SuggestionStatus.loading) return;

    setState(() {
      _status = _SuggestionStatus.loading;
      _errorMessage = null;
    });

    try {
      final suggestion = await _service.generateSuggestion(
        _inputController.text,
      );
      if (!mounted) return;
      setState(() {
        _suggestion = suggestion;
        _status = _SuggestionStatus.success;
      });
    } on AiHabitSetupException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message;
        _status = _SuggestionStatus.error;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = _unexpectedErrorMessage;
        _status = _SuggestionStatus.error;
      });
    }
  }

  void _accept() {
    final suggestion = _suggestion;
    if (suggestion == null) return;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: Padding(
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
              enabled: _status != _SuggestionStatus.loading,
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
        final suggestion = _suggestion;
        if (suggestion == null) return const SizedBox.shrink();
        return _SuggestionPreview(
          suggestion: suggestion,
          onAccept: _accept,
          onEdit: _editBeforeSaving,
          onCancel: () => Navigator.of(context).pop(),
        );
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

class _SuggestionPreview extends StatelessWidget {
  final HabitSuggestion suggestion;
  final VoidCallback onAccept;
  final VoidCallback onEdit;
  final VoidCallback onCancel;

  const _SuggestionPreview({
    required this.suggestion,
    required this.onAccept,
    required this.onEdit,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
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
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        OverflowBar(
          alignment: MainAxisAlignment.end,
          spacing: 8,
          children: [
            TextButton(onPressed: onCancel, child: const Text('Cancel')),
            TextButton(onPressed: onEdit, child: const Text('Edit')),
            FilledButton(onPressed: onAccept, child: const Text('Add habit')),
          ],
        ),
      ],
    );
  }
}
