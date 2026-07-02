/// AI-generated narrative for a week of habit data.
class AiWeeklyReview {
  final List<String> whatWentWell;
  final List<String> partialProgress;
  final List<String> patterns;
  final String focusNextWeek;

  /// Backward-compatible one-line summary used by older call sites/tests.
  final String summary;
  final String strongestInsight;
  final String weakestInsight;
  final String recommendation;

  const AiWeeklyReview({
    String? summary,
    String? strongestInsight,
    String? weakestInsight,
    String? recommendation,
    this.whatWentWell = const [],
    this.partialProgress = const [],
    this.patterns = const [],
    String? focusNextWeek,
  }) : summary = summary ?? '',
       strongestInsight = strongestInsight ?? '',
       weakestInsight = weakestInsight ?? '',
       recommendation = recommendation ?? focusNextWeek ?? '',
       focusNextWeek = focusNextWeek ?? recommendation ?? '';
}
