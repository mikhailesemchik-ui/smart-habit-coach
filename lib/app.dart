import 'package:flutter/material.dart';

import 'core/storage/legacy_migration_runner.dart';
import 'core/storage/user_data_schema_migrator.dart';
import 'features/navigation/presentation/main_navigation_screen.dart';
import 'features/onboarding/data/onboarding_storage.dart';
import 'features/onboarding/presentation/onboarding_screen.dart';
import 'features/profile/data/settings_storage.dart';
import 'features/profile/domain/app_settings.dart';
import 'features/startup/data/auth_session_gateway.dart';
import 'features/startup/presentation/startup_retry_screen.dart';

enum _StartupPhase { establishingIdentity, retryNeeded, ready }

/// Startup ordering (Phase 1A):
/// 1. Supabase is initialized in `main.dart` before this widget is built.
/// 2. Restore a persisted session, or complete anonymous sign-in
///    ([AuthSessionGateway.ensureSession]) — no namespaced storage is
///    touched before this succeeds.
/// 3. A real, non-blank UID is now available (never a passthrough).
/// 4. Run the one-time legacy-namespace migration
///    ([LegacyMigrationRunner]). A recorded conflict does not block
///    startup — both datasets are preserved and schema migration still
///    runs for the active namespaced destination.
/// 5. Run the per-UID local schema migration
///    ([LocalUserDataSchemaMigrator]) for the active namespace.
/// 6. Only once 4 and 5 have both succeeded are settings/onboarding/habit
///    data read.
/// 7. The normal app UI is shown.
///
/// If step 2 or step 5 fails, a non-destructive [StartupRetryScreen] is
/// shown instead of the normal app; retrying re-runs the whole pipeline
/// (steps 2-6), which is safe because every step is idempotent.
class SmartHabitCoachApp extends StatefulWidget {
  final AuthSessionGateway authGateway;
  final LocalUserDataSchemaMigrator schemaMigrator;

  SmartHabitCoachApp({
    super.key,
    this.authGateway = const SupabaseAuthSessionGateway(),
    LocalUserDataSchemaMigrator? schemaMigrator,
  }) : schemaMigrator = schemaMigrator ?? LocalUserDataSchemaMigrator();

  @override
  State<SmartHabitCoachApp> createState() => _SmartHabitCoachAppState();
}

enum _RetryReason { network, storageInit }

class _SmartHabitCoachAppState extends State<SmartHabitCoachApp> {
  final SettingsStorage _settingsStorage = SettingsStorage();
  final OnboardingStorage _onboardingStorage = OnboardingStorage();
  AppSettings _settings = AppSettings.defaults;
  _StartupPhase _phase = _StartupPhase.establishingIdentity;
  _RetryReason? _retryReason;
  bool _isRetrying = false;
  bool _isLoadingAppData = true;
  bool _showOnboarding = false;

  @override
  void initState() {
    super.initState();
    _runStartupPipeline();
  }

  /// Runs the full identity → legacy migration → schema migration
  /// pipeline. Safe to call repeatedly (each step is idempotent), so both
  /// the initial attempt and every Retry tap use this same method.
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

    // A recorded migration conflict is a valid, non-fatal outcome: both
    // datasets are preserved and startup continues for the active
    // namespaced destination, per the approved safe behavior.
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
    // Optimistic update first so theme/name changes feel instant, then
    // reconcile with the actually-persisted (stamped) settings once the
    // centralized write completes.
    setState(() => _settings = settings);
    final stamped = await _settingsStorage.updateSettings(settings);
    if (!mounted) return;
    setState(() => _settings = stamped);
  }

  Future<void> _completeOnboarding() async {
    await _onboardingStorage.setOnboardingCompleted();
    setState(() => _showOnboarding = false);
  }

  @override
  Widget build(BuildContext context) {
    final seedColor = Colors.teal;

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
