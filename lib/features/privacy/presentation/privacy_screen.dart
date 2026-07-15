import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_radii.dart';
import '../../../app/theme/app_spacing.dart';
import '../data/local_data_export_service.dart';
import '../domain/export_result.dart';
import 'privacy_keys.dart';

/// Explains what data the app stores and where, and lets the user export
/// their own local data for personal backup/review. Read-only — no delete
/// or destructive action of any kind exists on this screen.
class PrivacyScreen extends StatefulWidget {
  final LocalDataExportService? exportService;

  const PrivacyScreen({super.key, this.exportService});

  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

enum _ExportState { idle, loading, success, error }

class _PrivacyScreenState extends State<PrivacyScreen> {
  late final LocalDataExportService _exportService =
      widget.exportService ?? LocalDataExportService();

  _ExportState _state = _ExportState.idle;
  String? _jsonPreview;
  ExportFailure? _failure;
  bool _showCopiedMessage = false;

  Future<void> _export() async {
    setState(() {
      _state = _ExportState.loading;
      _showCopiedMessage = false;
    });
    final result = await _exportService.export();
    if (!mounted) return;
    setState(() {
      if (result.isSuccess) {
        _state = _ExportState.success;
        _jsonPreview = result.jsonString;
        _failure = null;
      } else {
        _state = _ExportState.error;
        _failure = result.failure;
        _jsonPreview = null;
      }
    });
  }

  Future<void> _copy() async {
    final json = _jsonPreview;
    if (json == null) return;
    await Clipboard.setData(ClipboardData(text: json));
    if (!mounted) return;
    setState(() => _showCopiedMessage = true);
  }

  String _errorMessage(ExportFailure failure) {
    return switch (failure.code) {
      ExportFailureCode.noActiveIdentity =>
        'No active identity — nothing to export yet.',
      ExportFailureCode.localReadFailure => 'Could not read your local data.',
      ExportFailureCode.serializationFailure =>
        'Could not build the export file.',
      ExportFailureCode.unknown => 'Something went wrong. Please try again.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Privacy & data')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Section(
            title: 'Local data',
            body:
                'Your habits and progress are stored on this device, under '
                'your current account identity. Anonymous and email '
                'identities each keep their own separate local data — '
                'switching identities never merges them together. Deleted '
                'habits are kept as hidden "tombstone" records for a short '
                'time so sync stays safe; they are not shown anywhere in '
                'the app.',
          ),
          _Section(
            title: 'Cloud sync',
            body:
                'If you choose to sync, your habits, coach suggestions, and '
                'preferences can be stored in our cloud database under your '
                'account. That data is protected so only your account can '
                'read or write it. Signing into a different account never '
                'automatically merges your anonymous data into it.',
          ),
          _Section(
            title: 'AI features',
            body:
                'AI Habit Setup and the Weekly Review send only the '
                'relevant habit or summary information needed to generate '
                'a result to our backend. Your API keys and credentials are '
                'never stored on your device or included in any export.',
          ),
          _Section(
            title: 'Notifications',
            body:
                'Reminders use your device\'s local notification '
                'permission. You can enable or disable notification '
                'permission at any time from the Profile screen or your '
                'device\'s system settings.',
          ),
          _Section(
            title: 'Export',
            body:
                'You can export a copy of your local data below for your '
                'own backup or review. The export includes your habits, '
                'coach suggestions, and settings, but never your sign-in '
                'tokens, passwords, or any cloud credentials.',
          ),
          _Section(
            title: 'Account deletion',
            body:
                'If you have signed in with an email account, you can '
                'delete your account from the Account screen. This '
                'permanently removes your account and cloud data. Export '
                'your data first if you want to keep a copy.',
          ),
          const SizedBox(height: 8),
          const Divider(),
          const SizedBox(height: 16),
          Text('Export local data', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: exportDataButtonKey,
            onPressed: _state == _ExportState.loading ? null : _export,
            icon: _state == _ExportState.loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_outlined),
            label: Text(
              _state == _ExportState.loading
                  ? 'Exporting…'
                  : 'Export local data',
            ),
          ),
          if (_state == _ExportState.error && _failure != null) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(
                _errorMessage(_failure!),
                key: exportErrorMessageKey,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          ],
          if (_state == _ExportState.success && _jsonPreview != null) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Export preview',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                TextButton.icon(
                  key: exportCopyButtonKey,
                  onPressed: _copy,
                  icon: const Icon(Icons.copy_outlined, size: 18),
                  label: const Text('Copy'),
                ),
              ],
            ),
            if (_showCopiedMessage)
              Semantics(
                liveRegion: true,
                child: Text(
                  'Copied to clipboard',
                  key: exportCopiedMessageKey,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: AppRadii.mediumRadius,
              ),
              child: SelectableText(
                _jsonPreview!,
                key: exportJsonPreviewKey,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String body;

  const _Section({required this.title, required this.body});

  IconData get _icon => switch (title) {
    'Local data' => Icons.smartphone_outlined,
    'Cloud sync' => Icons.cloud_outlined,
    'AI features' => Icons.auto_awesome_outlined,
    'Notifications' => Icons.notifications_outlined,
    'Export' => Icons.download_outlined,
    'Account deletion' => Icons.person_off_outlined,
    _ => Icons.info_outline,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_icon, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: AppSpacing.xs),
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            body,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
