import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;

import '../../auth/data/auth_repository.dart';
import '../../home/presentation/home_screen.dart';
import '../../profile/domain/app_settings.dart';
import '../../profile/presentation/profile_screen.dart';
import '../../progress/presentation/progress_screen.dart';
import 'navigation_keys.dart';

class MainNavigationScreen extends StatefulWidget {
  final AppSettings settings;
  final ValueChanged<AppSettings> onSettingsChanged;
  final Future<void> Function()? onIdentityChanged;
  final AuthRepository? accountAuthRepository;

  const MainNavigationScreen({
    super.key,
    required this.settings,
    required this.onSettingsChanged,
    this.onIdentityChanged,
    this.accountAuthRepository,
  });

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _selectedIndex = 0;
  int _homeRefreshToken = 0;
  int _progressRefreshToken = 0;

  void _onDestinationSelected(int index) {
    setState(() {
      _selectedIndex = index;
      if (index == 0) _homeRefreshToken++;
      if (index == 1) _progressRefreshToken++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screens = [
      HomeScreen(key: ValueKey(_homeRefreshToken)),
      ProgressScreen(key: ValueKey(_progressRefreshToken)),
      ProfileScreen(
        settings: widget.settings,
        onSettingsChanged: widget.onSettingsChanged,
        onIdentityChanged: widget.onIdentityChanged,
        accountAuthRepository: widget.accountAuthRepository,
      ),
    ];

    // Without this, Android paints its default (opaque) gesture-bar
    // background behind the nav bar instead of blending with it. Matches
    // the nav bar's own (white/near-white) background, not the page's.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value:
          (theme.brightness == Brightness.dark
                  ? SystemUiOverlayStyle.light
                  : SystemUiOverlayStyle.dark)
              .copyWith(
                systemNavigationBarColor: theme.colorScheme.surface,
                systemNavigationBarDividerColor: Colors.transparent,
                systemNavigationBarIconBrightness:
                    theme.brightness == Brightness.dark
                    ? Brightness.light
                    : Brightness.dark,
                systemNavigationBarContrastEnforced: false,
              ),
      child: Scaffold(
        body: IndexedStack(index: _selectedIndex, children: screens),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: _onDestinationSelected,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.today_outlined),
              selectedIcon: Icon(Icons.today),
              label: 'Today',
            ),
            NavigationDestination(
              icon: Icon(Icons.bar_chart_outlined),
              selectedIcon: Icon(Icons.bar_chart),
              label: 'Progress',
            ),
            NavigationDestination(
              key: profileNavigationDestinationKey,
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}
