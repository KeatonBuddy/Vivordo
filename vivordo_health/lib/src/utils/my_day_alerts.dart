/// The slow-moving alerts My Day shows under NOW. One shows; the rest wait
/// behind "N more".
enum MyDayAlert {
  burnout('burnout check'),
  trainingLoad('training load'),
  weeklyReview('weekly review');

  const MyDayAlert(this.label);

  /// How the "N more" row names it.
  final String label;
}

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
