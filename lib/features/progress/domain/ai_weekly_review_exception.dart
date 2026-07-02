/// User-facing failure when requesting or parsing an AI weekly review.
class AiWeeklyReviewException implements Exception {
  final String message;
  final bool isQuotaExceeded;
  final String? reason;
  final String? section;
  final String? sentence;
  final String? habitTitle;

  const AiWeeklyReviewException(
    this.message, {
    this.isQuotaExceeded = false,
    this.reason,
    this.section,
    this.sentence,
    this.habitTitle,
  });

  String get diagnosticSummary {
    final parts = [
      if (reason != null) 'reason=$reason',
      if (section != null) 'section=$section',
      if (habitTitle != null) 'habit=$habitTitle',
      if (sentence != null) 'sentence="$sentence"',
    ];
    return parts.isEmpty ? message : parts.join(' ');
  }

  @override
  String toString() => message;
}
