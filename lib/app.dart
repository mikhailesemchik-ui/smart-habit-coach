import 'package:flutter/material.dart';

import 'features/navigation/presentation/main_navigation_screen.dart';
import 'features/onboarding/data/onboarding_storage.dart';
import 'features/onboarding/presentation/onboarding_screen.dart';
import 'features/profile/data/settings_storage.dart';
import 'features/profile/domain/app_settings.dart';

class SmartHabitCoachApp extends StatefulWidget {
  const SmartHabitCoachApp({super.key});

  @override
  State<SmartHabitCoachApp> createState() => _SmartHabitCoachAppState();
}

class _SmartHabitCoachAppState extends State<SmartHabitCoachApp> {
  final SettingsStorage _settingsStorage = SettingsStorage();
  final OnboardingStorage _onboardingStorage = OnboardingStorage();
  AppSettings _settings = AppSettings.defaults;
  bool _isLoading = true;
  bool _showOnboarding = false;

  @override
  void initState() {
    super.initState();
    _loadInitialState();
  }

  Future<void> _loadInitialState() async {
    final settings = await _settingsStorage.loadSettings();
    final onboardingCompleted = await _onboardingStorage
        .isOnboardingCompleted();
    setState(() {
      _settings = settings;
      _showOnboarding = !onboardingCompleted;
      _isLoading = false;
    });
  }

  void _updateSettings(AppSettings settings) {
    setState(() => _settings = settings);
    _settingsStorage.saveSettings(settings);
  }

  Future<void> _completeOnboarding() async {
    await _onboardingStorage.setOnboardingCompleted();
    setState(() => _showOnboarding = false);
  }

  @override
  Widget build(BuildContext context) {
    final seedColor = Colors.teal;

    Widget home;
    if (_isLoading) {
      home = const Scaffold(body: Center(child: CircularProgressIndicator()));
    } else if (_showOnboarding) {
      home = OnboardingScreen(onCompleted: _completeOnboarding);
    } else {
      home = MainNavigationScreen(
        settings: _settings,
        onSettingsChanged: _updateSettings,
      );
    }

    return MaterialApp(
      title: 'Smart Habit Coach',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seedColor),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: _settings.themeMode,
      home: home,
    );
  }
}
