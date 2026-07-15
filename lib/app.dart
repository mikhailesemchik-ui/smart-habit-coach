import 'package:flutter/material.dart';

import 'app/theme/app_theme.dart';
import 'core/storage/legacy_migration_runner.dart';
import 'core/storage/user_data_schema_migrator.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/home/data/notification_reconciliation_service.dart';
import 'features/navigation/presentation/main_navigation_screen.dart';
import 'features/onboarding/data/onboarding_storage.dart';
import 'features/onboarding/presentation/onboarding_screen.dart';
import 'features/profile/data/settings_storage.dart';
import 'features/profile/domain/app_settings.dart';
import 'features/startup/data/auth_session_gateway.dart';
import 'features/startup/presentation/startup_retry_screen.dart';

enum _StartupPhase { establishingIdentity, retryNeeded, ready }

enum _RetryReason { network, storageInit }

class SmartHabitCoachApp extends StatefulWidget {
  final AuthSessionGateway authGateway;
  final LocalUserDataSchemaMigrator schemaMigrator;
  final AuthRepository? accountAuthRepository;
  final NotificationReconciliationService notificationReconciliationService;

  SmartHabitCoachApp({
    super.key,
    this.authGateway = const SupabaseAuthSessionGateway(),
    LocalUserDataSchemaMigrator? schemaMigrator,
    this.accountAuthRepository,
    NotificationReconciliationService? notificationReconciliationService,
  }) : schemaMigrator = schemaMigrator ?? LocalUserDataSchemaMigrator(),
       notificationReconciliationService =
           notificationReconciliationService ??
           NotificationReconciliationService();

  @override
  State<SmartHabitCoachApp> createState() => _SmartHabitCoachAppState();
}

class _SmartHabitCoachAppState extends State<SmartHabitCoachApp> {
  final SettingsStorage _settingsStorage = SettingsStorage();
  final OnboardingStorage _onboardingStorage = OnboardingStorage();

  AppSettings _settings = AppSettings.defaults;
  _StartupPhase _phase = _StartupPhase.establishingIdentity;
  _RetryReason? _retryReason;
  bool _isRetrying = false;
  bool _isLoadingAppData = true;
  bool _showOnboarding = false;
  int _identityGeneration = 0;

  @override
  void initState() {
    super.initState();
    _runStartupPipeline();
  }

  Future<void> _runStartupPipeline() async {
    final established = await widget.authGateway.ensureSession();
    if (!mounted) return;
    if (!established) {
      setState(() {
        _phase = _StartupPhase.retryNeeded;
        _retryReason = _RetryReason.network;
      });
      return;
    }

    await LegacyMigrationRunner().run();
    if (!mounted) return;

    final schemaReady = await widget.schemaMigrator.run();
    if (!mounted) return;
    if (!schemaReady) {
      setState(() {
        _phase = _StartupPhase.retryNeeded;
        _retryReason = _RetryReason.storageInit;
      });
      return;
    }

    setState(() => _phase = _StartupPhase.ready);
    await _loadInitialState();
  }

  Future<void> _retry() async {
    if (_isRetrying) return;
    setState(() => _isRetrying = true);
    await _runStartupPipeline();
    if (!mounted) return;
    setState(() => _isRetrying = false);
  }

  Future<void> _handleIdentityChanged() async {
    setState(() => _isLoadingAppData = true);
    final schemaReady = await widget.schemaMigrator.run();
    if (!mounted) return;
    if (!schemaReady) {
      setState(() {
        _phase = _StartupPhase.retryNeeded;
        _retryReason = _RetryReason.storageInit;
        _isLoadingAppData = false;
      });
      return;
    }

    _identityGeneration++;
    // Reconciles reminders for the newly-active identity, canceling
    // anything scheduled under the previously-active one first — notification
    // IDs are derived from habit id alone, so two different identities could
    // otherwise collide or leave stale reminders behind after a switch.
    await widget.notificationReconciliationService.reconcile();
    await _loadInitialState();
  }

  Future<void> _loadInitialState() async {
    final settings = await _settingsStorage.loadSettings();
    final onboardingCompleted = await _onboardingStorage
        .isOnboardingCompleted();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _showOnboarding = !onboardingCompleted;
      _isLoadingAppData = false;
    });
  }

  Future<void> _updateSettings(AppSettings settings) async {
    setState(() => _settings = settings);
    final stamped = await _settingsStorage.updateSettings(settings);
    if (!mounted) return;
    setState(() => _settings = stamped);
  }

  Future<void> _completeOnboarding() async {
    await _onboardingStorage.setOnboardingCompleted();
    if (!mounted) return;
    setState(() => _showOnboarding = false);
  }

  @override
  Widget build(BuildContext context) {
    Widget home;
    if (_phase == _StartupPhase.retryNeeded) {
      home = StartupRetryScreen(
        isRetrying: _isRetrying,
        onRetry: _retry,
        title: _retryReason == _RetryReason.storageInit
            ? 'Could not finish setting up your data'
            : 'Connect to the internet to set up Smart Habit Coach',
        message: _retryReason == _RetryReason.storageInit
            ? 'Something went wrong preparing your local data. Please try again.'
            : 'Smart Habit Coach needs an internet connection once to set '
                  'up your private, on-device identity. After that, it '
                  'works fully offline.',
      );
    } else if (_phase == _StartupPhase.establishingIdentity ||
        _isLoadingAppData) {
      home = const Scaffold(body: Center(child: CircularProgressIndicator()));
    } else if (_showOnboarding) {
      home = OnboardingScreen(onCompleted: _completeOnboarding);
    } else {
      home = MainNavigationScreen(
        key: ValueKey(_identityGeneration),
        settings: _settings,
        onSettingsChanged: _updateSettings,
        onIdentityChanged: _handleIdentityChanged,
        accountAuthRepository: widget.accountAuthRepository,
      );
    }

    return MaterialApp(
      title: 'Smart Habit Coach',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: _settings.themeMode,
      home: home,
    );
  }
}
