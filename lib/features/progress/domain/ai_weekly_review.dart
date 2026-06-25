/// AI-generated narrative for a week of habit completions. The strongest
/// and weakest day themselves remain locally calculated and authoritative;
/// this only carries the AI's written insights about them.
class AiWeeklyReview {
  final String summary;
  final String strongestInsight;
  final String weakestInsight;
  final String recommendation;

  const AiWeeklyReview({
    required this.summary,
    required this.strongestInsight,
    required this.weakestInsight,
    required this.recommendation,
  });
}
