import '../../coach/domain/adaptive_suggestion.dart';
import '../../home/domain/habit.dart';
import '../../profile/domain/app_settings.dart';
import 'cloud_result.dart';

DateTime _readRequiredTimestamp(Object? raw, String field) {
  if (raw is! String) {
    throw CloudMappingException('$field missing');
  }
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    throw CloudMappingException('$field invalid');
  }
  return parsed;
}

DateTime? _readOptionalTimestamp(Object? raw, String field) {
  if (raw == null) return null;
  if (raw is! String) {
    throw CloudMappingException('$field invalid');
  }
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    throw CloudMappingException('$field invalid');
  }
  return parsed;
}

String _readExpectedUserId(Map<String, dynamic> row, String expectedUserId) {
  final userId = row['user_id'];
  if (userId is! String || userId.trim().isEmpty) {
    throw const CloudMappingException('user_id missing');
  }
  if (userId != expectedUserId) {
    throw const CloudMappingException('user_id mismatch');
  }
  return userId;
}

String _readNonBlankString(Map<String, dynamic> row, String field) {
  final value = row[field];
  if (value is! String || value.trim().isEmpty) {
    throw CloudMappingException('$field missing');
  }
  return value;
}

Map<String, dynamic> _readPayload(Map<String, dynamic> row) {
  final payload = row['payload'];
  if (payload is! Map) {
    throw const CloudMappingException('payload missing');
  }
  return Map<String, dynamic>.from(payload);
}

Map<String, dynamic> _withCloudTimestamps({
  required Map<String, dynamic> payload,
  required String id,
  required DateTime createdAt,
  required DateTime updatedAt,
  DateTime? deletedAt,
}) {
  final merged = {
    ...payload,
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };
  if (deletedAt != null) {
    merged['deletedAt'] = deletedAt.toIso8601String();
  } else {
    merged.remove('deletedAt');
  }
  return merged;
}

class CloudHabitRecord {
  final String userId;
  final Habit habit;
  final Map<String, dynamic> payload;

  const CloudHabitRecord({
    required this.userId,
    required this.habit,
    required this.payload,
  });

  factory CloudHabitRecord.fromHabit({
    required String userId,
    required Habit habit,
  }) {
    return CloudHabitRecord(
      userId: userId,
      habit: habit,
      payload: habit.toJson(),
    );
  }

  static CloudHabitRecord fromRow(
    Map<String, dynamic> row, {
    required String expectedUserId,
  }) {
    final userId = _readExpectedUserId(row, expectedUserId);
    final id = _readNonBlankString(row, 'id');
    final createdAt = _readRequiredTimestamp(row['created_at'], 'created_at');
    final updatedAt = _readRequiredTimestamp(row['updated_at'], 'updated_at');
    final deletedAt = _readOptionalTimestamp(row['deleted_at'], 'deleted_at');
    final payload = _readPayload(row);
    final payloadId = payload['id'];
    if (payloadId is String && payloadId != id) {
      throw const CloudMappingException('payload id mismatch');
    }

    try {
      final habit = Habit.fromJson(
        _withCloudTimestamps(
          payload: payload,
          id: id,
          createdAt: createdAt,
          updatedAt: updatedAt,
          deletedAt: deletedAt,
        ),
      );
      return CloudHabitRecord(userId: userId, habit: habit, payload: payload);
    } catch (_) {
      throw const CloudMappingException('habit payload invalid');
    }
  }

  Map<String, dynamic> toRow({required String expectedUserId}) {
    if (userId != expectedUserId) {
      throw const CloudMappingException('user_id mismatch');
    }
    final mergedPayload = {...payload, ...habit.toJson()};
    return {
      'user_id': userId,
      'id': habit.id,
      'created_at': habit.createdAt.toIso8601String(),
      'updated_at': habit.updatedAt.toIso8601String(),
      'deleted_at': habit.deletedAt?.toIso8601String(),
      'payload': mergedPayload,
    };
  }
}

class CloudAdaptiveSuggestionRecord {
  final String userId;
  final AdaptiveHabitSuggestion suggestion;
  final Map<String, dynamic> payload;

  const CloudAdaptiveSuggestionRecord({
    required this.userId,
    required this.suggestion,
    required this.payload,
  });

  factory CloudAdaptiveSuggestionRecord.fromSuggestion({
    required String userId,
    required AdaptiveHabitSuggestion suggestion,
  }) {
    return CloudAdaptiveSuggestionRecord(
      userId: userId,
      suggestion: suggestion,
      payload: suggestion.toJson(),
    );
  }

  static CloudAdaptiveSuggestionRecord fromRow(
    Map<String, dynamic> row, {
    required String expectedUserId,
  }) {
    final userId = _readExpectedUserId(row, expectedUserId);
    final id = _readNonBlankString(row, 'id');
    final habitId = _readNonBlankString(row, 'habit_id');
    final createdAt = _readRequiredTimestamp(row['created_at'], 'created_at');
    final updatedAt = _readRequiredTimestamp(row['updated_at'], 'updated_at');
    final deletedAt = _readOptionalTimestamp(row['deleted_at'], 'deleted_at');
    final payload = _readPayload(row);
    final payloadId = payload['id'];
    final payloadHabitId = payload['habitId'];
    if (payloadId is String && payloadId != id) {
      throw const CloudMappingException('payload id mismatch');
    }
    if (payloadHabitId is String && payloadHabitId != habitId) {
      throw const CloudMappingException('payload habitId mismatch');
    }

    final suggestion = AdaptiveHabitSuggestion.fromJson(
      _withCloudTimestamps(
        payload: {...payload, 'habitId': habitId},
        id: id,
        createdAt: createdAt,
        updatedAt: updatedAt,
        deletedAt: deletedAt,
      ),
    );
    if (suggestion == null) {
      throw const CloudMappingException('suggestion payload invalid');
    }
    return CloudAdaptiveSuggestionRecord(
      userId: userId,
      suggestion: suggestion,
      payload: payload,
    );
  }

  Map<String, dynamic> toRow({required String expectedUserId}) {
    if (userId != expectedUserId) {
      throw const CloudMappingException('user_id mismatch');
    }
    final mergedPayload = {...payload, ...suggestion.toJson()};
    return {
      'user_id': userId,
      'id': suggestion.id,
      'habit_id': suggestion.habitId,
      'created_at': suggestion.createdAt.toIso8601String(),
      'updated_at': suggestion.updatedAt.toIso8601String(),
      'deleted_at': suggestion.deletedAt?.toIso8601String(),
      'payload': mergedPayload,
    };
  }
}

class CloudSettingsRecord {
  final String userId;
  final AppSettings settings;
  final Map<String, dynamic> payload;

  const CloudSettingsRecord({
    required this.userId,
    required this.settings,
    required this.payload,
  });

  factory CloudSettingsRecord.fromSettings({
    required String userId,
    required AppSettings settings,
  }) {
    return CloudSettingsRecord(
      userId: userId,
      settings: settings,
      payload: settings.toJson(),
    );
  }

  static CloudSettingsRecord fromRow(
    Map<String, dynamic> row, {
    required String expectedUserId,
  }) {
    final userId = _readExpectedUserId(row, expectedUserId);
    final updatedAt = _readRequiredTimestamp(row['updated_at'], 'updated_at');
    final payload = _readPayload(row);
    try {
      final settings = AppSettings.fromJson({
        ...payload,
        'updatedAt': updatedAt.toIso8601String(),
      });
      return CloudSettingsRecord(
        userId: userId,
        settings: settings,
        payload: payload,
      );
    } catch (_) {
      throw const CloudMappingException('settings payload invalid');
    }
  }

  Map<String, dynamic> toRow({required String expectedUserId}) {
    if (userId != expectedUserId) {
      throw const CloudMappingException('user_id mismatch');
    }
    final mergedPayload = {...payload, ...settings.toJson()};
    return {
      'user_id': userId,
      'updated_at': settings.updatedAt.toIso8601String(),
      'payload': mergedPayload,
    };
  }
}
