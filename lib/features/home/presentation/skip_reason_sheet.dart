import 'package:flutter/material.dart';

import '../../../app/theme/app_spacing.dart';
import '../domain/habit.dart';

class SkipReasonSelection {
  final HabitSkipReason? reason;
  final String? note;

  const SkipReasonSelection({required this.reason, this.note});
}

Future<SkipReasonSelection?> showSkipReasonSheet({
  required BuildContext context,
  required Habit habit,
  required DateTime date,
}) {
  return showModalBottomSheet<SkipReasonSelection>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _SkipReasonSheet(habit: habit, date: date),
  );
}

class _SkipReasonSheet extends StatefulWidget {
  final Habit habit;
  final DateTime date;

  const _SkipReasonSheet({required this.habit, required this.date});

  @override
  State<_SkipReasonSheet> createState() => _SkipReasonSheetState();
}

class _SkipReasonSheetState extends State<_SkipReasonSheet> {
  late HabitSkipReason? _selected = widget.habit.skipReasonFor(widget.date);
  late final TextEditingController _noteController = TextEditingController(
    text: widget.habit.skipReasonNoteFor(widget.date) ?? '',
  );

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _save() {
    final trimmedNote = _noteController.text.trim();
    Navigator.of(context).pop(
      SkipReasonSelection(
        reason: _selected,
        note: trimmedNote.isEmpty ? null : trimmedNote,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);
    final isKeyboardClosed = mediaQuery.viewInsets.bottom == 0;
    final bottomInset = mediaQuery.viewInsets.bottom > 0
        ? mediaQuery.viewInsets.bottom
        : mediaQuery.viewPadding.bottom;
    final footerBottomPadding =
        bottomInset + (isKeyboardClosed ? AppSpacing.xl : AppSpacing.md);

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          top: AppSpacing.lg,
          bottom: footerBottomPadding,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Why was it missed?', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            RadioGroup<HabitSkipReason>(
              groupValue: _selected,
              onChanged: (HabitSkipReason? value) {
                if (value != null) setState(() => _selected = value);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final reason in HabitSkipReason.values)
                    RadioListTile<HabitSkipReason>(
                      contentPadding: EdgeInsets.zero,
                      title: Text(habitSkipReasonLabel(reason)),
                      value: reason,
                    ),
                ],
              ),
            ),
            if (_selected == HabitSkipReason.other) ...[
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _noteController,
                decoration: const InputDecoration(
                  labelText: 'Optional note',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextButton(
                    onPressed: _selected == null
                        ? null
                        : () => Navigator.of(
                            context,
                          ).pop(const SkipReasonSelection(reason: null)),
                    child: const Text('Clear reason'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _selected == null ? null : _save,
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
