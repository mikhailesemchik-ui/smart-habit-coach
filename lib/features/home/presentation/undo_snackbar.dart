import 'package:flutter/material.dart';

import '../../../app/theme/app_spacing.dart';

/// Shows a consistent, compact "message · Undo" snackbar shared by every
/// habit-related screen (Today, Habit Details, ...).
///
/// Deliberately does NOT use [SnackBarAction]: on a real device with
/// accessibility navigation active, Flutter disables a SnackBar's
/// auto-dismiss timer entirely whenever `action` is set, so the bar never
/// times out. Undo is embedded as a compact [TextButton] inside `content`
/// instead, which auto-dismisses reliably while still looking and behaving
/// like a native snackbar action.
///
/// Always calls [ScaffoldMessengerState.hideCurrentSnackBar] (never
/// `removeCurrentSnackBar`/`clearSnackBars`) so both replacing an earlier
/// snackbar and dismissing after Undo use the normal animated exit.
ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showUndoSnackBar(
  BuildContext context, {
  required String message,
  required VoidCallback onUndo,
  Duration duration = const Duration(seconds: 3),
}) {
  final theme = Theme.of(context);
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  return messenger.showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 18,
            color: theme.colorScheme.surface,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(message)),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.primaryContainer,
              textStyle: const TextStyle(fontWeight: FontWeight.w600),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              minimumSize: const Size(0, 36),
            ),
            onPressed: () {
              onUndo();
              messenger.hideCurrentSnackBar();
            },
            child: const Text('Undo'),
          ),
        ],
      ),
      duration: duration,
    ),
  );
}
