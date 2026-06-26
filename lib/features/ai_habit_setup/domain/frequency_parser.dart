/// Returns the number of times per week explicitly stated in [goal],
/// or null when no clear frequency pattern is present.
///
/// Valid range: 1–7. Values outside this range are ignored.
/// Only concrete numeric or English word patterns are matched.
int? parseFrequencyFromGoal(String goal) {
  final text = goal.toLowerCase();

  const wordMap = {
    'once': 1,
    'one': 1,
    'twice': 2,
    'two': 2,
    'three': 3,
    'four': 4,
    'five': 5,
    'six': 6,
    'seven': 7,
  };

  // "once/twice/three times (a|per) week"
  final wordPattern = RegExp(
    r'\b(once|twice|one|two|three|four|five|six|seven)'
    r'(?:\s+times?)?\s+(?:a|per)\s+week\b',
  );
  final wordMatch = wordPattern.firstMatch(text);
  if (wordMatch != null) {
    final n = wordMap[wordMatch.group(1)!];
    if (n != null && n >= 1 && n <= 7) return n;
  }

  // "Nx weekly", "N times (a|per) week[ly]"
  final numPattern = RegExp(
    r'\b(\d+)(?:x\s+(?:weekly|per\s+week)|\s+times?\s+(?:a|per)\s+week(?:ly)?)\b',
  );
  final numMatch = numPattern.firstMatch(text);
  if (numMatch != null) {
    final n = int.tryParse(numMatch.group(1)!);
    if (n != null && n >= 1 && n <= 7) return n;
  }

  return null;
}
