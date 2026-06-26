/// User-facing failure when requesting or parsing an AI weekly review.
class AiWeeklyReviewException implements Exception {
  final String message;
  final bool isQuotaExceeded;

  const AiWeeklyReviewException(this.message, {this.isQuotaExceeded = false});

  @override
  String toString() => message;
}
