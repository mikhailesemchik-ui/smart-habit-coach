import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/ai_habit_setup_exception.dart';
import '../domain/ai_habit_suggestion_source.dart';
import '../domain/habit_suggestion.dart';
import '../domain/habit_suggestion_response.dart';

const _requestFailedMessage =
    "Couldn't generate a suggestion right now. Please try again.";
const aiHabitSetupQuotaMessage =
    "You've reached today's AI habit limit. Try again tomorrow.";

/// Calls the `generate-habit` Supabase Edge Function to turn a free-form
/// goal description into a structured [HabitSuggestion].
class AiHabitSetupService implements AiHabitSuggestionSource {
  final SupabaseClient _client;

  AiHabitSetupService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  @override
  Future<HabitSuggestion> generateSuggestion(String goal) async {
    final FunctionResponse response;
    try {
      response = await _client.functions
          .invoke('generate-habit', body: {'goal': goal})
          .timeout(const Duration(seconds: 20));
    } on FunctionException catch (e) {
      if (isAiHabitSetupQuotaExceeded(e.status, e.details)) {
        throw const AiHabitSetupException(aiHabitSetupQuotaMessage);
      }
      throw const AiHabitSetupException(_requestFailedMessage);
    } catch (_) {
      throw const AiHabitSetupException(_requestFailedMessage);
    }

    return parseHabitSuggestionResponse(response.data);
  }
}

bool isAiHabitSetupQuotaExceeded(int status, Object? data) {
  if (status == 429) return true;
  if (data is! Map) return false;

  final error = data['error'];
  if (error is! Map) return false;

  return error['code'] == 'quota_exceeded';
}
