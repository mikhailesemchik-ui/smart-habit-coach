/// A single, local-only, last-known-good copy of a UID's raw user-owned
/// data, captured immediately before a destructive or conflict-prone
/// replacement operation (e.g. tombstone delete). Only one snapshot is
/// kept per UID — creating a new one replaces the previous.
///
/// Contents are raw JSON (already-encoded habit/suggestion/settings/sync
/// maps) rather than typed model objects, so this class never needs to
/// know about model shape changes across app versions — it just carries
/// whatever [HabitStorage.loadHabitsRaw] etc. produced at the time.
///
/// Never contains auth tokens or Supabase credentials.
class RecoverySnapshot {
  static const schemaVersion = 1;

  final DateTime createdAt;
  final String reason;
  final List<Map<String, dynamic>> habits;
  final List<Map<String, dynamic>> suggestions;
  final Map<String, dynamic>? settings;
  final Map<String, dynamic>? syncMetadata;

  const RecoverySnapshot({
    required this.createdAt,
    required this.reason,
    required this.habits,
    required this.suggestions,
    this.settings,
    this.syncMetadata,
  });

  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': schemaVersion,
      'createdAt': createdAt.toIso8601String(),
      'reason': reason,
      'habits': habits,
      'suggestions': suggestions,
      if (settings != null) 'settings': settings,
      if (syncMetadata != null) 'syncMetadata': syncMetadata,
    };
  }

  /// Returns `null` for malformed input rather than throwing, so a corrupt
  /// snapshot never crashes the app that would otherwise rely on it.
  static RecoverySnapshot? fromJson(Map<String, dynamic> json) {
    final createdAtRaw = json['createdAt'];
    final reason = json['reason'];
    final habitsRaw = json['habits'];
    final suggestionsRaw = json['suggestions'];

    if (createdAtRaw is! String || reason is! String) return null;
    final createdAt = DateTime.tryParse(createdAtRaw);
    if (createdAt == null) return null;
    if (habitsRaw is! List || suggestionsRaw is! List) return null;

    final settings = json['settings'];
    final syncMetadata = json['syncMetadata'];

    return RecoverySnapshot(
      createdAt: createdAt,
      reason: reason,
      habits: habitsRaw.whereType<Map<String, dynamic>>().toList(),
      suggestions: suggestionsRaw.whereType<Map<String, dynamic>>().toList(),
      settings: settings is Map<String, dynamic> ? settings : null,
      syncMetadata: syncMetadata is Map<String, dynamic> ? syncMetadata : null,
    );
  }
}
