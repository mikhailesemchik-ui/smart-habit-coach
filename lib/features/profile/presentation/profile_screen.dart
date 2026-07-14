import 'package:flutter/material.dart';

import '../../auth/data/auth_repository.dart';
import '../../auth/presentation/account_screen.dart';
import '../../home/data/notification_service.dart';
import '../../home/presentation/archived_habits_screen.dart';
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
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: CircleAvatar(
              radius: 32,
              child: Text(
                settings.displayName.trim().isNotEmpty
                    ? settings.displayName.trim()[0].toUpperCase()
                    : '?',
                style: theme.textTheme.headlineMedium,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            settings.displayName,
            key: const Key('profileDisplayName'),
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Text('Display name', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            onChanged: _onDisplayNameChanged,
          ),
          const SizedBox(height: 24),
          Text('Theme', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<ThemeMode>(
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              padding: WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
            segments: const [
              ButtonSegment(value: ThemeMode.system, label: Text('System')),
              ButtonSegment(value: ThemeMode.light, label: Text('Light')),
              ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
            ],
            selected: {settings.themeMode},
            onSelectionChanged: _onThemeModeChanged,
          ),
          const SizedBox(height: 24),
          Text('Start of week', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<StartOfWeek>(
            segments: const [
              ButtonSegment(value: StartOfWeek.monday, label: Text('Monday')),
              ButtonSegment(value: StartOfWeek.sunday, label: Text('Sunday')),
            ],
            selected: {settings.startOfWeek},
            onSelectionChanged: _onStartOfWeekChanged,
          ),
          const SizedBox(height: 24),
          const Divider(),
          Text('Notifications', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          _buildNotificationStatus(theme),
          const SizedBox(height: 24),
          const Divider(),
          ListTile(
            key: profileAccountTileKey,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.account_circle_outlined),
            title: const Text('Account'),
            subtitle: const Text('Link, sign in, or sign out'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openAccount,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.archive_outlined),
            title: const Text('Archived habits'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ArchivedHabitsScreen()),
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
