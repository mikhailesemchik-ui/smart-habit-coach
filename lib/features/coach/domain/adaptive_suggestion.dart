/// The kind of adjustment an Adaptive Habit Coach suggestion proposes.
enum AdaptiveSuggestionType {
  addMinimumVersion,
  reduceQuantitativeTarget,
  changeScheduledTime,
  reduceFrequency,
  reviewSchedule,
}

/// Lifecycle state of a suggestion once shown to the user.
enum AdaptiveSuggestionStatus { pending, applied, adjusted, kept, rejected }

AdaptiveSuggestionType? _typeFromString(Object? raw) {
  if (raw is! String) return null;
  for (final type in AdaptiveSuggestionType.values) {
    if (type.name == raw) return type;
  }
  return null;
}

AdaptiveSuggestionStatus? _statusFromString(Object? raw) {
  if (raw is! String) return null;
  for (final status in AdaptiveSuggestionStatus.values) {
    if (status.name == raw) return status;
  }
  return null;
}

Map<String, num>? _readEvidence(Object? raw) {
  if (raw is! Map) return null;
  final evidence = <String, num>{};
  for (final entry in raw.entries) {
    final key = entry.key;
    final value = entry.value;
    if (key is! String || value is! num) continue;
    evidence[key] = value;
  }
  return evidence;
}

List<int>? _readWeekdays(Object? raw) {
  if (raw is! List) return null;
  final days = raw.whereType<int>().where((d) => d >= 1 && d <= 7).toList();
  return days.isEmpty ? null : days;
}

/// A locally-detected, deterministic suggestion for adjusting a habit's plan.
///
/// Suggestions are generated from structured local usage data only. Wording
/// and delivery (AI, UI) are added in a later phase; this model only carries
/// the evidence and a proposed adjustment.
class AdaptiveHabitSuggestion {
  final String id;
  final String habitId;
  final AdaptiveSuggestionType type;
  final AdaptiveSuggestionStatus status;

  final DateTime createdAt;
  final DateTime analysisStart;
  final DateTime analysisEnd;

  /// Machine-readable identifier for which rule produced this suggestion,
  /// so evidence can be interpreted without storing prose.
  final String evidenceCode;

  /// Structured counts/ratios backing the suggestion (e.g. occurrence
  /// counts, ratios). Must never contain free-text notes.
  final Map<String, num> evidence;

  final double? proposedTargetValue;
  final String? proposedTime;
  final List<int>? proposedWeekdays;

  /// Snapshot of the habit's target at the moment this suggestion was
  /// created. Required (alongside [originalUnit]) before direct Apply is
  /// offered, so a later change to the habit can be detected as stale.
  /// Suggestions created before Phase 3 never have this set.
  final double? originalTargetValue;

  /// Snapshot of the habit's unit at the moment this suggestion was
  /// created. May legitimately be null (a unit-less habit) — [applyEligible]
  /// callers must check [originalTargetValue] to know whether a snapshot
  /// was taken at all.
  final String? originalUnit;

  const AdaptiveHabitSuggestion({
    required this.id,
    required this.habitId,
    required this.type,
    this.status = AdaptiveSuggestionStatus.pending,
    required this.createdAt,
    required this.analysisStart,
    required this.analysisEnd,
    required this.evidenceCode,
    this.evidence = const {},
    this.proposedTargetValue,
    this.proposedTime,
    this.proposedWeekdays,
    this.originalTargetValue,
    this.originalUnit,
  });

  AdaptiveHabitSuggestion copyWith({
    AdaptiveSuggestionStatus? status,
    String? evidenceCode,
    double? proposedTargetValue,
    String? proposedTime,
    List<int>? proposedWeekdays,
  }) {
    return AdaptiveHabitSuggestion(
      id: id,
      habitId: habitId,
      type: type,
      status: status ?? this.status,
      createdAt: createdAt,
      analysisStart: analysisStart,
      analysisEnd: analysisEnd,
      evidenceCode: evidenceCode ?? this.evidenceCode,
      evidence: evidence,
      proposedTargetValue: proposedTargetValue ?? this.proposedTargetValue,
      proposedTime: proposedTime ?? this.proposedTime,
      proposedWeekdays: proposedWeekdays ?? this.proposedWeekdays,
      originalTargetValue: originalTargetValue,
      originalUnit: originalUnit,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'habitId': habitId,
      'type': type.name,
      'status': status.name,
      'createdAt': createdAt.toIso8601String(),
      'analysisStart': analysisStart.toIso8601String(),
      'analysisEnd': analysisEnd.toIso8601String(),
      'evidenceCode': evidenceCode,
      if (evidence.isNotEmpty) 'evidence': evidence,
      if (proposedTargetValue != null)
        'proposedTargetValue': proposedTargetValue,
      if (proposedTime != null) 'proposedTime': proposedTime,
      if (proposedWeekdays != null) 'proposedWeekdays': proposedWeekdays,
      if (originalTargetValue != null)
        'originalTargetValue': originalTargetValue,
      if (originalUnit != null) 'originalUnit': originalUnit,
    };
  }

  /// Parses a suggestion from stored JSON. Returns null for malformed
  /// entries so callers can safely skip them rather than crash.
  static AdaptiveHabitSuggestion? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final habitId = json['habitId'];
    final type = _typeFromString(json['type']);
    final status =
        _statusFromString(json['status']) ?? AdaptiveSuggestionStatus.pending;
    final evidenceCode = json['evidenceCode'];
    final createdAt = DateTime.tryParse(json['createdAt']?.toString() ?? '');
    final analysisStart = DateTime.tryParse(
      json['analysisStart']?.toString() ?? '',
    );
    final analysisEnd = DateTime.tryParse(
      json['analysisEnd']?.toString() ?? '',
    );

    if (id is! String ||
        habitId is! String ||
        type == null ||
        evidenceCode is! String ||
        createdAt == null ||
        analysisStart == null ||
        analysisEnd == null) {
      return null;
    }

    final proposedTargetValue = json['proposedTargetValue'];
    final proposedTime = json['proposedTime'];
    final originalTargetValue = json['originalTargetValue'];
    final originalUnit = json['originalUnit'];

    return AdaptiveHabitSuggestion(
      id: id,
      habitId: habitId,
      type: type,
      status: status,
      createdAt: createdAt,
      analysisStart: analysisStart,
      analysisEnd: analysisEnd,
      evidenceCode: evidenceCode,
      evidence: _readEvidence(json['evidence']) ?? const {},
      proposedTargetValue: proposedTargetValue is num
          ? proposedTargetValue.toDouble()
          : null,
      proposedTime: proposedTime is String ? proposedTime : null,
      proposedWeekdays: _readWeekdays(json['proposedWeekdays']),
      // Absent on suggestions created before Phase 3 — left null so those
      // stay loadable but ineligible for direct Apply.
      originalTargetValue: originalTargetValue is num
          ? originalTargetValue.toDouble()
          : null,
      originalUnit: originalUnit is String ? originalUnit : null,
    );
  }
}
