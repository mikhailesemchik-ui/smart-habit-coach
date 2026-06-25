/// User-facing failure when requesting or parsing an AI weekly review.
class AiWeeklyReviewException implements Exception {
  final String message;

  const AiWeeklyReviewException(this.message);

  @override
  String toString() => message;
}
