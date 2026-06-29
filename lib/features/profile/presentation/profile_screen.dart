import 'package:flutter/material.dart';

import '../../home/presentation/archived_habits_screen.dart';
import '../domain/app_settings.dart';

class ProfileScreen extends StatefulWidget {
  final AppSettings settings;
  final ValueChanged<AppSettings> onSettingsChanged;

  const ProfileScreen({
    super.key,
    required this.settings,
    required this.onSettingsChanged,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.settings.displayName);
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
}
