import 'package:flutter/material.dart';

import '../../../app/theme/app_radii.dart';
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
          left: 16,
          right: 16,
          top: 16,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.outline,
                  borderRadius: AppRadii.pillRadius,
                ),
              ),
            ),
            Text(
              widget.title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              maxLines: 4,
              maxLength: 300,
              decoration: const InputDecoration(hintText: 'Add a note…'),
            ),
            const SizedBox(height: 4),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                if (widget.existingNote != null)
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(''),
                    child: const Text('Delete note'),
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
