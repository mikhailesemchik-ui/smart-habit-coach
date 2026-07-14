/// Schema version for [LocalDataExport.toJson]. Bump only when the export
/// shape changes in a way a reader would need to know about.
const localDataExportVersion = 1;

/// Hardcoded rather than read via a package-info dependency — Phase 6 avoids
/// adding a new package for two static strings that rarely change.
const _appName = 'Smart Habit Coach';
const _appVersion = '0.1.0';

/// A snapshot of one UID's local application data, suitable for a personal
/// backup/review export. Contains no auth tokens, session data, or cloud
/// credentials — see [LocalDataExportService] for what is deliberately
/// excluded.
class LocalDataExport {
  final DateTime generatedAt;
  final String activeUid;
  final List<Map<String, dynamic>> habitsRaw;
  final List<Map<String, dynamic>> adaptiveSuggestionsRaw;
  final Map<String, dynamic> appSettings;
  final Map<String, dynamic> syncMetadata;

  /// The single latest local recovery snapshot, included in full (Option A
  /// from the Phase 6 spec): it is already-tombstone-aware raw app data
  /// with no secrets of its own (see [RecoverySnapshot]'s own contract), so
  /// including it here is just another safe, clearly-labeled backup of the
  /// same kind of data as the rest of this export. `null` when no snapshot
  /// has ever been created for this UID.
  final Map<String, dynamic>? recoverySnapshot;

  const LocalDataExport({
    required this.generatedAt,
    required this.activeUid,
    required this.habitsRaw,
    required this.adaptiveSuggestionsRaw,
    required this.appSettings,
    required this.syncMetadata,
    this.recoverySnapshot,
  });

  /// Fixed top-level key order and stable list ordering (by `id`), so the
  /// same underlying data always serializes to the same JSON string.
  Map<String, dynamic> toJson() {
    return {
      'exportVersion': localDataExportVersion,
      'generatedAt': generatedAt.toIso8601String(),
      'appName': _appName,
      'appVersion': _appVersion,
      'activeUid': activeUid,
      'habits': _sortedById(habitsRaw),
      'adaptiveSuggestions': _sortedById(adaptiveSuggestionsRaw),
      'appSettings': appSettings,
      'syncMetadata': syncMetadata,
      if (recoverySnapshot != null) 'recoverySnapshot': recoverySnapshot,
      'excludedData':
          'This export never includes auth tokens, session data, API keys, '
          'or cloud credentials. It is intended for personal backup and '
          'review only.',
    };
  }

  static List<Map<String, dynamic>> _sortedById(
    List<Map<String, dynamic>> records,
  ) {
    final copy = List<Map<String, dynamic>>.of(records);
    copy.sort((a, b) => '${a['id']}'.compareTo('${b['id']}'));
    return copy;
  }
}
