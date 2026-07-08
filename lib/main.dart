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

  // Identity establishment (persisted session, or anonymous sign-in with a
  // visible Retry state on failure) now happens inside the widget tree —
  // see SmartHabitCoachApp's startup state machine in app.dart — so it can
  // show a reactive UI instead of blocking/swallowing here.
  runApp(SmartHabitCoachApp());
}
