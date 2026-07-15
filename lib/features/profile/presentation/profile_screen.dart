import 'package:flutter/material.dart';

import '../../../app/theme/app_radii.dart';
import '../../../app/theme/app_spacing.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/presentation/account_screen.dart';
import '../../home/data/notification_service.dart';
import '../../home/presentation/archived_habits_screen.dart';
import '../../privacy/presentation/privacy_screen.dart';
import '../domain/app_settings.dart';
import 'profile_keys.dart';

class ProfileScreen extends StatefulWidget {
  final AppSettings settings;
  final ValueChanged<AppSettings> onSettingsChanged;
  final Future<void> Function()? onIdentityChanged;
  final AuthRepository? accountAuthRepository;
  final NotificationService? notificationService;

  const ProfileScreen({
    super.key,
    required this.settings,
    required this.onSettingsChanged,
    this.onIdentityChanged,
    this.accountAuthRepository,
    this.notificationService,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController _nameController;
  late final NotificationService _notifications =
      widget.notificationService ?? NotificationService();
  NotificationPermissionStatus _permissionStatus =
      NotificationPermissionStatus.unknown;
  bool _isRequestingPermission = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.settings.displayName);
    _loadPermissionStatus();
  }

  Future<void> _loadPermissionStatus() async {
    final status = await _notifications.permissionStatus();
    if (!mounted) return;
    setState(() => _permissionStatus = status);
  }

  Future<void> _requestPermission() async {
    if (_isRequestingPermission) return;
    setState(() => _isRequestingPermission = true);
    await _notifications.requestPermission();
    final status = await _notifications.permissionStatus();
    if (!mounted) return;
    setState(() {
      _permissionStatus = status;
      _isRequestingPermission = false;
    });
  }

  @override
  void didUpdateWidget(covariant ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings.displayName != widget.settings.displayName &&
        _nameController.text != widget.settings.displayName) {
      _nameController.text = widget.settings.displayName;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _onDisplayNameChanged(String value) {
    widget.onSettingsChanged(widget.settings.copyWith(displayName: value));
  }

  void _onThemeModeChanged(Set<ThemeMode> selection) {
    widget.onSettingsChanged(
      widget.settings.copyWith(themeMode: selection.first),
    );
  }

  void _onStartOfWeekChanged(Set<StartOfWeek> selection) {
    widget.onSettingsChanged(
      widget.settings.copyWith(startOfWeek: selection.first),
    );
  }

  Future<void> _openAccount() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AccountScreen(
          authRepository: widget.accountAuthRepository,
          onIdentityChanged: widget.onIdentityChanged,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = widget.settings;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: AppRadii.largeRadius,
            ),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: theme.colorScheme.surface,
                  child: Text(
                    settings.displayName.trim().isNotEmpty
                        ? settings.displayName.trim()[0].toUpperCase()
                        : '?',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  settings.displayName,
                  key: const Key('profileDisplayName'),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.lg,
            ),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: AppRadii.largeRadius,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Display name', style: theme.textTheme.titleSmall),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _nameController,
                  onChanged: _onDisplayNameChanged,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text('Theme', style: theme.textTheme.titleSmall),
                const SizedBox(height: AppSpacing.sm),
                SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    padding: WidgetStatePropertyAll(
                      EdgeInsets.symmetric(horizontal: 4),
                    ),
                  ),
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text('System'),
                    ),
                    ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                    ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                  ],
                  selected: {settings.themeMode},
                  onSelectionChanged: _onThemeModeChanged,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text('Start of week', style: theme.textTheme.titleSmall),
                const SizedBox(height: AppSpacing.sm),
                SegmentedButton<StartOfWeek>(
                  segments: const [
                    ButtonSegment(
                      value: StartOfWeek.monday,
                      label: Text('Monday'),
                    ),
                    ButtonSegment(
                      value: StartOfWeek.sunday,
                      label: Text('Sunday'),
                    ),
                  ],
                  selected: {settings.startOfWeek},
                  onSelectionChanged: _onStartOfWeekChanged,
                ),
                const SizedBox(height: AppSpacing.lg),
                const Divider(),
                const SizedBox(height: AppSpacing.md),
                Text('Notifications', style: theme.textTheme.titleSmall),
                const SizedBox(height: AppSpacing.sm),
                _buildNotificationStatus(theme),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _ProfileEntryRow(
            entryKey: profileAccountTileKey,
            icon: Icons.account_circle_outlined,
            title: 'Account',
            subtitle: 'Link, sign in, or sign out',
            onTap: _openAccount,
          ),
          const SizedBox(height: AppSpacing.sm),
          _ProfileEntryRow(
            icon: Icons.archive_outlined,
            title: 'Archived habits',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ArchivedHabitsScreen()),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _ProfileEntryRow(
            entryKey: profilePrivacyTileKey,
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy & data',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PrivacyScreen()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationStatus(ThemeData theme) {
    final (label, copy) = switch (_permissionStatus) {
      NotificationPermissionStatus.granted => ('Reminders are enabled', null),
      NotificationPermissionStatus.denied => (
        'Reminders are turned off',
        'Habit reminders may not appear. You can try enabling them again.',
      ),
      NotificationPermissionStatus.unknown => (
        'Reminder status unavailable',
        'We could not check your notification permission on this device.',
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, key: notificationPermissionStatusKey),
        if (copy != null) ...[
          const SizedBox(height: 4),
          Text(
            copy,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (_permissionStatus != NotificationPermissionStatus.granted) ...[
          const SizedBox(height: 8),
          OutlinedButton(
            key: notificationPermissionRequestButtonKey,
            onPressed: _isRequestingPermission ? null : _requestPermission,
            child: Text(
              _isRequestingPermission ? 'Requesting…' : 'Enable reminders',
            ),
          ),
        ],
      ],
    );
  }
}

/// Rounded, tappable settings entry row (Account/Archived habits/Privacy).
class _ProfileEntryRow extends StatelessWidget {
  final Key? entryKey;
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  const _ProfileEntryRow({
    this.entryKey,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      key: entryKey,
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: AppRadii.largeRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.largeRadius,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 20, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
