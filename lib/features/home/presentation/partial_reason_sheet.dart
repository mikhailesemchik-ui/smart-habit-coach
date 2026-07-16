import 'package:flutter/material.dart';

import '../domain/habit.dart';

class PartialReasonSelection {
  final HabitPartialReason? reason;
  final String? note;

  const PartialReasonSelection({required this.reason, this.note});
}

Future<PartialReasonSelection?> showPartialReasonSheet({
  required BuildContext context,
  required Habit habit,
  required DateTime date,
}) {
  return showModalBottomSheet<PartialReasonSelection>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _PartialReasonSheet(habit: habit, date: date),
  );
}

class _PartialReasonSheet extends StatefulWidget {
  final Habit habit;
  final DateTime date;

  const _PartialReasonSheet({required this.habit, required this.date});

  @override
  State<_PartialReasonSheet> createState() => _PartialReasonSheetState();
}

class _PartialReasonSheetState extends State<_PartialReasonSheet> {
  late HabitPartialReason? _selected = widget.habit.partialReasonFor(
    widget.date,
  );
  late final TextEditingController _noteController = TextEditingController(
    text: widget.habit.partialReasonNoteFor(widget.date) ?? '',
  );

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _save() {
    final trimmedNote = _noteController.text.trim();
    Navigator.of(context).pop(
      PartialReasonSelection(
        reason: _selected,
        note: trimmedNote.isEmpty ? null : trimmedNote,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
            Text(
              "Why wasn't the target reached?",
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            RadioGroup<HabitPartialReason>(
              groupValue: _selected,
              onChanged: (HabitPartialReason? value) {
                if (value != null) setState(() => _selected = value);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final reason in HabitPartialReason.values)
                    RadioListTile<HabitPartialReason>(
                      contentPadding: EdgeInsets.zero,
                      title: Text(habitPartialReasonLabel(reason)),
                      value: reason,
                    ),
                ],
              ),
            ),
            if (_selected == HabitPartialReason.other) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _noteController,
                decoration: const InputDecoration(
                  labelText: 'Optional note',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
            const SizedBox(height: 12),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: _selected == null
                      ? null
                      : () => Navigator.of(
                          context,
                        ).pop(const PartialReasonSelection(reason: null)),
                  child: const Text('Clear reason'),
                ),
                FilledButton(
                  onPressed: _selected == null ? null : _save,
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
