import 'package:flutter/material.dart';

import '../../home/presentation/home_screen.dart';
import '../../profile/domain/app_settings.dart';
import '../../profile/presentation/profile_screen.dart';
import '../../progress/presentation/progress_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  final AppSettings settings;
  final ValueChanged<AppSettings> onSettingsChanged;

  const MainNavigationScreen({
    super.key,
    required this.settings,
    required this.onSettingsChanged,
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
    final screens = [
      HomeScreen(key: ValueKey(_homeRefreshToken)),
      ProgressScreen(key: ValueKey(_progressRefreshToken)),
      ProfileScreen(
        settings: widget.settings,
        onSettingsChanged: widget.onSettingsChanged,
      ),
    ];

    return Scaffold(
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
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
