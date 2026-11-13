/// The slow-moving alerts My Day shows under NOW, each as a row that opens
/// out to its card.
enum MyDayAlert { burnout, trainingLoad, weeklyReview }

/// The alerts that apply, most serious first: a burnout warning, strained
/// training load, burnout worth watching, high training load, then Sunday's
/// weekly review. [burnout] is the burnout check's level and
/// [trainingLoad] the training-load state; anything calmer isn't an alert.
List<MyDayAlert> rankMyDayAlerts({
  String? burnout,
  String? trainingLoad,
  bool weeklyReview = false,
}) {
  int? rank(MyDayAlert alert) => switch (alert) {
    MyDayAlert.burnout => switch (burnout) {
      'warning' => 0,
      'watch' => 2,
      _ => null,
    },
    MyDayAlert.trainingLoad => switch (trainingLoad) {
      'strained' => 1,
      'high' => 3,
      _ => null,
    },
    MyDayAlert.weeklyReview => weeklyReview ? 4 : null,
  };
  return [
    for (final alert in MyDayAlert.values)
      if (rank(alert) != null) alert,
  ]..sort((a, b) => rank(a)!.compareTo(rank(b)!));
}

/// Whether a burnout or training-load alert is showing on My Day. A plan
/// that leaves room then says to go easy rather than "room to spare", which
/// would say the opposite of the card below it.
bool goEasy({String? burnout, String? trainingLoad}) =>
    rankMyDayAlerts(burnout: burnout, trainingLoad: trainingLoad).isNotEmpty;

/// The brief's headline when the day's plan leaves room ([goEasy]).
String roomToSpareHeadline({String? burnout, String? trainingLoad}) =>
    goEasy(burnout: burnout, trainingLoad: trainingLoad)
    ? 'Room today, but go easy'
    : 'Room to spare today';
