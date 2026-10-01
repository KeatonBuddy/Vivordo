/// When someone's main work or classes usually end, in minutes after
/// midnight. Items after it count as after hours in Demand and Effort
/// (docs/scores.md).
const int kDefaultDayWrapUpMinutes = 17 * 60;

/// The value saved from the signup answer (q10): minutes after midnight, or
/// null for "It varies", which falls back to [kDefaultDayWrapUpMinutes]. A
/// stored null still records that the question was answered.
int? dayWrapUpMinutes(Map<String, dynamic> answers) {
  final answer = answers['q10'];
  if (answer == 'varies') return null;
  if (answer is int && answer >= 0 && answer < 24 * 60) return answer;
  return kDefaultDayWrapUpMinutes;
}
