import 'dart:collection';
import 'dart:convert';

/// Deterministic, order-independent JSON comparison key. Used only for the
/// exact-timestamp tie-break case — never for ordering by content
/// otherwise. Recursively sorts map keys so two structurally-equal JSON
/// payloads always canonicalize identically regardless of field order.
String canonicalJson(Map<String, dynamic> json) => jsonEncode(_sortKeys(json));

dynamic _sortKeys(dynamic value) {
  if (value is Map) {
    final sorted = SplayTreeMap<String, dynamic>();
    for (final entry in value.entries) {
      sorted[entry.key.toString()] = _sortKeys(entry.value);
    }
    return sorted;
  }
  if (value is List) return value.map(_sortKeys).toList();
  return value;
}

/// Outcome of comparing one local/remote record pair (or singleton).
///
/// Rules (documented once here, shared by habits and suggestions):
/// - local-only (no remote row with this id): always upload. This covers
///   both a genuinely new/edited local record and the "remote row was
///   somehow lost" self-heal case — either way, re-pushing the unchanged
///   local record is a safe, idempotent no-op if the row already exists
///   remotely.
/// - remote-only: always download; never marked dirty locally, since it
///   did not originate from a local change.
/// - both exist: compare `updatedAt`. Strictly newer wins. On an exact
///   timestamp tie: identical canonical payloads are `unchanged`; otherwise
///   a tombstone wins over a non-tombstone (a delete should never be lost
///   to a stale concurrent edit); if both/neither are tombstones, fall back
///   to a stable canonical-JSON string comparison (remote wins if its
///   canonical JSON sorts greater) — deterministic and reproducible, never
///   wall-clock `now()`.
enum RecordMergeAction { uploadLocal, applyRemote, unchanged }

class MergeDecision<TRemote> {
  final Set<String> uploadIds;
  final Map<String, TRemote> applyRemote;
  final int unchangedCount;
  final int uploadedTombstoneCount;
  final int downloadedTombstoneCount;
  final int conflictsResolvedLocal;
  final int conflictsResolvedRemote;

  const MergeDecision({
    required this.uploadIds,
    required this.applyRemote,
    required this.unchangedCount,
    required this.uploadedTombstoneCount,
    required this.downloadedTombstoneCount,
    required this.conflictsResolvedLocal,
    required this.conflictsResolvedRemote,
  });
}

/// Plans a `mergeNormally` resolution for one entity type (habits or
/// suggestions), given local and remote records already scoped to a single
/// UID by the caller. Pure and side-effect free — performs no I/O.
MergeDecision<TRemote> planMerge<TLocal, TRemote>({
  required List<TLocal> local,
  required List<TRemote> remote,
  required String Function(TLocal) localId,
  required DateTime Function(TLocal) localUpdatedAt,
  required bool Function(TLocal) localIsTombstone,
  required Map<String, dynamic> Function(TLocal) localJson,
  required String Function(TRemote) remoteId,
  required DateTime Function(TRemote) remoteUpdatedAt,
  required bool Function(TRemote) remoteIsTombstone,
  required Map<String, dynamic> Function(TRemote) remoteJson,
}) {
  final localById = {for (final l in local) localId(l): l};
  final remoteById = {for (final r in remote) remoteId(r): r};
  final allIds = {...localById.keys, ...remoteById.keys};

  final uploadIds = <String>{};
  final applyRemote = <String, TRemote>{};
  var unchanged = 0;
  var uploadedTombstones = 0;
  var downloadedTombstones = 0;
  var conflictsLocal = 0;
  var conflictsRemote = 0;

  for (final id in allIds) {
    final l = localById[id];
    final r = remoteById[id];

    if (l != null && r == null) {
      uploadIds.add(id);
      if (localIsTombstone(l)) uploadedTombstones++;
      continue;
    }
    if (l == null && r != null) {
      applyRemote[id] = r;
      if (remoteIsTombstone(r)) downloadedTombstones++;
      continue;
    }
    if (l == null || r == null) continue; // unreachable given allIds

    final lUpdated = localUpdatedAt(l);
    final rUpdated = remoteUpdatedAt(r);

    if (lUpdated.isAfter(rUpdated)) {
      uploadIds.add(id);
      conflictsLocal++;
      continue;
    }
    if (rUpdated.isAfter(lUpdated)) {
      applyRemote[id] = r;
      conflictsRemote++;
      if (remoteIsTombstone(r)) downloadedTombstones++;
      continue;
    }

    // Exact timestamp tie.
    final lCanonical = canonicalJson(localJson(l));
    final rCanonical = canonicalJson(remoteJson(r));
    if (lCanonical == rCanonical) {
      unchanged++;
      continue;
    }
    final lTomb = localIsTombstone(l);
    final rTomb = remoteIsTombstone(r);
    if (lTomb && !rTomb) {
      uploadIds.add(id);
      conflictsLocal++;
    } else if (rTomb && !lTomb) {
      applyRemote[id] = r;
      conflictsRemote++;
      downloadedTombstones++;
    } else if (rCanonical.compareTo(lCanonical) > 0) {
      applyRemote[id] = r;
      conflictsRemote++;
      if (rTomb) downloadedTombstones++;
    } else {
      uploadIds.add(id);
      conflictsLocal++;
      if (lTomb) uploadedTombstones++;
    }
  }

  return MergeDecision(
    uploadIds: uploadIds,
    applyRemote: applyRemote,
    unchangedCount: unchanged,
    uploadedTombstoneCount: uploadedTombstones,
    downloadedTombstoneCount: downloadedTombstones,
    conflictsResolvedLocal: conflictsLocal,
    conflictsResolvedRemote: conflictsRemote,
  );
}
