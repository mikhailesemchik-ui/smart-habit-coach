import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: _supabaseUrl,
    publishableKey: _supabaseAnonKey,
  );

  await _ensureAuthenticatedSession();

  runApp(const SmartHabitCoachApp());
}

/// Ensures every app install has a real Supabase session so AI edge
/// functions (which require a valid JWT) can be called. Anonymous sign-in
/// failures (e.g. no network on first launch) are swallowed so the app can
/// still start and work fully offline; AI features handle a missing
/// session as a normal request failure with their existing retry UI.
Future<void> _ensureAuthenticatedSession() async {
  final auth = Supabase.instance.client.auth;
  if (auth.currentSession != null) return;

  try {
    await auth.signInAnonymously();
  } catch (_) {
    // Ignored: AI features surface this as a normal failure with Retry.
  }
}
