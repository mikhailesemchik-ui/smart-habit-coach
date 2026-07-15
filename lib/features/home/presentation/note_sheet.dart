import 'package:flutter/material.dart';

import '../../../app/theme/app_radii.dart';
import '../../../app/theme/app_spacing.dart';
import '../domain/habit.dart';

/// Shows a bottom sheet for adding or editing a per-date note.
///
/// Returns:
/// - null   — the user cancelled (no-op).
/// - ''     — the user deleted or cleared the note.
/// - text   — the new note text to store.
Future<String?> showNoteSheet({
  required BuildContext context,
  required Habit habit,
  required DateTime date,
  String title = 'Note for today',
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _NoteSheet(existingNote: habit.noteFor(date), title: title),
  );
}

class _NoteSheet extends StatefulWidget {
  final String? existingNote;
  final String title;

  const _NoteSheet({required this.existingNote, required this.title});

  @override
  State<_NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends State<_NoteSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.existingNote ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          top: AppSpacing.md,
          bottom: AppSpacing.lg + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                decoration: BoxDecoration(
                  color: theme.colorScheme.outline,
                  borderRadius: AppRadii.pillRadius,
                ),
              ),
            ),
            Text(
              widget.title,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _controller,
              minLines: 5,
              maxLines: 8,
              maxLength: 300,
              textAlignVertical: TextAlignVertical.top,
              decoration: const InputDecoration(
                hintText: 'How did it go today? Add a quick note…',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              spacing: AppSpacing.sm,
              children: [
                if (widget.existingNote != null)
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).pop(''),
                    icon: Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: theme.colorScheme.error,
                    ),
                    label: Text(
                      'Delete note',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(_controller.text),
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
