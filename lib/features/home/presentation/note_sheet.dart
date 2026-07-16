import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;

import '../../../app/theme/app_radii.dart';
import '../../../app/theme/app_spacing.dart';
import '../domain/habit.dart';

/// Shows a bottom sheet for adding or editing a per-date note.
///
/// Returns:
/// - null   -- the user cancelled (no-op).
/// - ''     -- the user deleted or cleared the note.
/// - text   -- the new note text to store.
Future<String?> showNoteSheet({
  required BuildContext context,
  required Habit habit,
  required DateTime date,
  String title = 'Note for today',
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
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

  String _charactersLeftLabel(int currentLength, int? maxLength) {
    final remaining = ((maxLength ?? 300) - currentLength).clamp(0, 300);
    final noun = remaining == 1 ? 'character' : 'characters';
    return '$remaining $noun left';
  }

  Color _charactersLeftColor(
    ThemeData theme,
    int currentLength,
    int? maxLength,
  ) {
    final remaining = ((maxLength ?? 300) - currentLength).clamp(0, 300);
    if (remaining <= 20) return theme.colorScheme.error;
    return theme.colorScheme.onSurfaceVariant;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);
    final maxHeight = mediaQuery.size.height * 0.76;
    final keyboardInset = mediaQuery.viewInsets.bottom;
    final isKeyboardClosed = keyboardInset == 0;
    final footerBottomPadding = isKeyboardClosed
        ? mediaQuery.viewPadding.bottom + AppSpacing.lg
        : AppSpacing.md;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value:
          (theme.brightness == Brightness.dark
                  ? SystemUiOverlayStyle.light
                  : SystemUiOverlayStyle.dark)
              .copyWith(
                systemNavigationBarColor: Colors.transparent,
                systemNavigationBarDividerColor: Colors.transparent,
                systemNavigationBarIconBrightness:
                    theme.brightness == Brightness.dark
                    ? Brightness.light
                    : Brightness.dark,
                systemNavigationBarContrastEnforced: false,
              ),
      child: Padding(
        padding: EdgeInsets.only(bottom: keyboardInset),
        child: Material(
          color: theme.colorScheme.surface,
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadii.sheetTopRadius,
          ),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              padding: EdgeInsets.only(
                left: AppSpacing.lg,
                right: AppSpacing.lg,
                top: AppSpacing.md,
                bottom: footerBottomPadding,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SheetHandle(),
                  Text(
                    widget.title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _controller,
                    minLines: 4,
                    maxLines: 6,
                    maxLength: 300,
                    textAlignVertical: TextAlignVertical.top,
                    decoration: InputDecoration(
                      hintText: 'How did it go today? Add a quick note...',
                      hintStyle: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHighest,
                      contentPadding: const EdgeInsets.all(AppSpacing.md),
                      border: OutlineInputBorder(
                        borderRadius: AppRadii.largeRadius,
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: AppRadii.largeRadius,
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: AppRadii.largeRadius,
                        borderSide: BorderSide(
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.32,
                          ),
                        ),
                      ),
                      counterText: '',
                    ),
                    buildCounter:
                        (
                          _, {
                          required currentLength,
                          required isFocused,
                          required maxLength,
                        }) => Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding: const EdgeInsets.only(top: AppSpacing.xs),
                            child: Text(
                              _charactersLeftLabel(currentLength, maxLength),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: _charactersLeftColor(
                                  theme,
                                  currentLength,
                                  maxLength,
                                ),
                              ),
                            ),
                          ),
                        ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      if (widget.existingNote != null) ...[
                        Semantics(
                          button: true,
                          label: 'Delete note',
                          child: IconButton(
                            onPressed: () => Navigator.of(context).pop(''),
                            tooltip: 'Delete note',
                            icon: const Icon(Icons.delete_outline),
                            color: theme.colorScheme.error,
                            visualDensity: VisualDensity.compact,
                            style: IconButton.styleFrom(
                              backgroundColor: theme.colorScheme.error
                                  .withValues(alpha: 0.08),
                              minimumSize: const Size(44, 44),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                      ],
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        flex: 2,
                        child: FilledButton(
                          onPressed: () =>
                              Navigator.of(context).pop(_controller.text),
                          child: const Text('Save'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(
          top: AppSpacing.xs,
          bottom: AppSpacing.md,
        ),
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.outline,
            borderRadius: AppRadii.pillRadius,
          ),
        ),
      ),
    );
  }
}
