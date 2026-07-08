/// Per-UID local sync bookkeeping: which records changed locally since the
/// last successful sync, and when sync last ran. Local-only in Phase 1C —
/// nothing here talks to a network or cloud table yet.
///
/// Contains no user data content (no habit titles, notes, evidence text,
/// etc.) — only ids and machine-readable status, safe to inspect for
/// diagnostics.
class SyncMetadata {
  final Set<String> dirtyHabitIds;
  final Set<String> dirtySuggestionIds;
  final bool preferencesDirty;
  final DateTime? lastSuccessfulSyncAt;
  final DateTime? lastSyncAttemptAt;
  final String? lastSyncErrorCode;

  const SyncMetadata({
    this.dirtyHabitIds = const {},
    this.dirtySuggestionIds = const {},
    this.preferencesDirty = false,
    this.lastSuccessfulSyncAt,
    this.lastSyncAttemptAt,
    this.lastSyncErrorCode,
  });

  static const empty = SyncMetadata();

  SyncMetadata copyWith({
    Set<String>? dirtyHabitIds,
    Set<String>? dirtySuggestionIds,
    bool? preferencesDirty,
    Object? lastSuccessfulSyncAt = _omit,
    Object? lastSyncAttemptAt = _omit,
    Object? lastSyncErrorCode = _omit,
  }) {
    return SyncMetadata(
      dirtyHabitIds: dirtyHabitIds ?? this.dirtyHabitIds,
      dirtySuggestionIds: dirtySuggestionIds ?? this.dirtySuggestionIds,
      preferencesDirty: preferencesDirty ?? this.preferencesDirty,
      lastSuccessfulSyncAt: identical(lastSuccessfulSyncAt, _omit)
          ? this.lastSuccessfulSyncAt
          : lastSuccessfulSyncAt as DateTime?,
      lastSyncAttemptAt: identical(lastSyncAttemptAt, _omit)
          ? this.lastSyncAttemptAt
          : lastSyncAttemptAt as DateTime?,
      lastSyncErrorCode: identical(lastSyncErrorCode, _omit)
          ? this.lastSyncErrorCode
          : lastSyncErrorCode as String?,
    );
  }

  static const Object _omit = Object();

  Map<String, dynamic> toJson() {
    return {
      if (dirtyHabitIds.isNotEmpty) 'dirtyHabitIds': dirtyHabitIds.toList(),
      if (dirtySuggestionIds.isNotEmpty)
        'dirtySuggestionIds': dirtySuggestionIds.toList(),
      if (preferencesDirty) 'preferencesDirty': preferencesDirty,
      if (lastSuccessfulSyncAt != null)
        'lastSuccessfulSyncAt': lastSuccessfulSyncAt!.toIso8601String(),
      if (lastSyncAttemptAt != null)
        'lastSyncAttemptAt': lastSyncAttemptAt!.toIso8601String(),
      if (lastSyncErrorCode != null) 'lastSyncErrorCode': lastSyncErrorCode,
    };
  }

  factory SyncMetadata.fromJson(Map<String, dynamic> json) {
    return SyncMetadata(
      dirtyHabitIds: _readStringSet(json['dirtyHabitIds']),
      dirtySuggestionIds: _readStringSet(json['dirtySuggestionIds']),
      preferencesDirty: json['preferencesDirty'] == true,
      lastSuccessfulSyncAt: _readTimestamp(json['lastSuccessfulSyncAt']),
      lastSyncAttemptAt: _readTimestamp(json['lastSyncAttemptAt']),
      lastSyncErrorCode: json['lastSyncErrorCode'] is String
          ? json['lastSyncErrorCode'] as String
          : null,
    );
  }

  static Set<String> _readStringSet(Object? raw) {
    if (raw is! List) return {};
    return raw.whereType<String>().toSet();
  }

  static DateTime? _readTimestamp(Object? raw) {
    if (raw is! String) return null;
    return DateTime.tryParse(raw);
  }
}
