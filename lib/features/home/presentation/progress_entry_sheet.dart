import 'package:flutter/material.dart';

import '../domain/habit.dart';

/// Shows a bottom sheet for logging numeric progress on a quantitative habit.
/// Returns the entered value (may be 0 to clear), or null if dismissed.
Future<double?> showProgressEntrySheet({
  required BuildContext context,
  required Habit habit,
  required DateTime date,
}) {
  return showModalBottomSheet<double>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ProgressEntrySheet(habit: habit, date: date),
  );
}

class _ProgressEntrySheet extends StatefulWidget {
  final Habit habit;
  final DateTime date;

  const _ProgressEntrySheet({required this.habit, required this.date});

  @override
  State<_ProgressEntrySheet> createState() => _ProgressEntrySheetState();
}

class _ProgressEntrySheetState extends State<_ProgressEntrySheet> {
  late final TextEditingController _controller;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.habit.progressFor(widget.date);
    _controller = TextEditingController(
      text: existing > 0 ? habitProgressLabel(existing) : '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _increment(double amount) {
    final current = double.tryParse(_controller.text.trim()) ?? 0.0;
    final next = current + amount;
    setState(() {
      _controller.text = habitProgressLabel(next);
      _hasError = false;
    });
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
  }

  void _save() {
    final raw = _controller.text.trim();
    if (raw.isEmpty) {
      // Save requires an explicit value; use Reset to clear progress to 0.
      setState(() => _hasError = true);
      return;
    }
    final parsed = double.tryParse(raw);
    if (parsed == null || parsed < 0) {
      setState(() => _hasError = true);
      return;
    }
    Navigator.of(context).pop(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final target = widget.habit.targetValue ?? 0;
    final unit = widget.habit.unit ?? '';
    final current = double.tryParse(_controller.text.trim()) ?? 0.0;
    final ratio = target > 0 ? (current / target).clamp(0.0, 1.0) : 0.0;
    final increments = _quickIncrements(target);

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
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
            Text(widget.habit.title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 2),
            if (target > 0)
              Text(
                'Target: ${habitProgressLabel(target)}${unit.isNotEmpty ? " $unit" : ""}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: 12),
            if (target > 0) ...[
              LinearProgressIndicator(value: ratio),
              const SizedBox(height: 12),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: unit.isNotEmpty ? 'Amount ($unit)' : 'Amount',
                      border: const OutlineInputBorder(),
                      errorText: _hasError ? 'Enter a valid number' : null,
                    ),
                    onChanged: (_) => setState(() {
                      _hasError = false;
                    }),
                  ),
                ),
                if (increments.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Column(
                    children: [
                      for (final inc in increments)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: OutlinedButton(
                            onPressed: () => _increment(inc),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(64, 40),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                            ),
                            child: Text('+${habitProgressLabel(inc)}'),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
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
                TextButton(
                  onPressed: () => Navigator.of(context).pop(0.0),
                  child: const Text('Reset'),
                ),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _controller,
                  builder: (context, value, _) {
                    return FilledButton(
                      onPressed: value.text.trim().isEmpty ? null : _save,
                      child: const Text('Save'),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

List<double> _quickIncrements(double target) {
  if (target <= 0) return const [1];
  if (target <= 5) return const [0.5, 1];
  if (target <= 20) return const [1, 5];
  if (target <= 100) return const [5, 10];
  if (target <= 500) return const [50, 100];
  return const [100, 500];
}
