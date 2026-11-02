/// The units Vivordo shows and accepts (Settings → Units, saved as
/// `preferences.units`). Values are stored the same way whatever the
/// choice: body weight in kg, height in cm, distance in km and lift weight
/// in lb (`weightLbs`); they're converted only for display and entry, so
/// switching never changes saved data or personal bests.
enum MassUnit { kg, lb }

enum DistanceUnit { km, mi }

enum HeightUnit { cm, ftIn }

const kgPerLb = 0.45359237;
const kmPerMile = 1.609344;
const cmPerInch = 2.54;

class Units {
  const Units({
    required this.bodyWeight,
    required this.liftWeight,
    required this.distance,
    required this.height,
  });

  final MassUnit bodyWeight;
  final MassUnit liftWeight;
  final DistanceUnit distance;
  final HeightUnit height;

  static const metric = Units(
    bodyWeight: MassUnit.kg,
    liftWeight: MassUnit.kg,
    distance: DistanceUnit.km,
    height: HeightUnit.cm,
  );

  /// The defaults for a device region: the US uses lb, miles and feet;
  /// Canada lb and feet but kilometres; everywhere else is metric.
  factory Units.forCountry(String? country) => switch (country?.toUpperCase()) {
    'US' || 'LR' || 'MM' => const Units(
      bodyWeight: MassUnit.lb,
      liftWeight: MassUnit.lb,
      distance: DistanceUnit.mi,
      height: HeightUnit.ftIn,
    ),
    'CA' => const Units(
      bodyWeight: MassUnit.lb,
      liftWeight: MassUnit.lb,
      distance: DistanceUnit.km,
      height: HeightUnit.ftIn,
    ),
    _ => metric,
  };

  /// [saved] (`preferences.units`) over [defaults], one measure at a time.
  factory Units.fromPreferences(Object? saved, Units defaults) {
    final map = saved is Map ? saved : const {};
    T pick<T extends Enum>(List<T> values, String key, T fallback) =>
        values.where((v) => v.name == map[key]).firstOrNull ?? fallback;
    return Units(
      bodyWeight: pick(MassUnit.values, 'bodyWeight', defaults.bodyWeight),
      liftWeight: pick(MassUnit.values, 'liftWeight', defaults.liftWeight),
      distance: pick(DistanceUnit.values, 'distance', defaults.distance),
      height: pick(HeightUnit.values, 'height', defaults.height),
    );
  }

  Map<String, String> toMap() => {
    'bodyWeight': bodyWeight.name,
    'liftWeight': liftWeight.name,
    'distance': distance.name,
    'height': height.name,
  };

  Units copyWith({
    MassUnit? bodyWeight,
    MassUnit? liftWeight,
    DistanceUnit? distance,
    HeightUnit? height,
  }) => Units(
    bodyWeight: bodyWeight ?? this.bodyWeight,
    liftWeight: liftWeight ?? this.liftWeight,
    distance: distance ?? this.distance,
    height: height ?? this.height,
  );

  // --- Body weight (stored in kg).
  String get bodyWeightLabel => _massLabel(bodyWeight);
  double bodyWeightValue(double kg) =>
      bodyWeight == MassUnit.kg ? kg : kg / kgPerLb;
  double bodyWeightToKg(double value) =>
      bodyWeight == MassUnit.kg ? value : value * kgPerLb;
  String formatBodyWeight(double kg, {int decimals = 1}) =>
      '${formatNumber(bodyWeightValue(kg), decimals)} $bodyWeightLabel';

  // --- Lift weight (stored in lb).
  String get liftLabel => _massLabel(liftWeight);
  double liftValue(double lbs) =>
      liftWeight == MassUnit.lb ? lbs : lbs * kgPerLb;
  double liftToLbs(double value) =>
      liftWeight == MassUnit.lb ? value : value / kgPerLb;

  /// "135" or "61.2": up to one decimal, as typed.
  String liftNumber(double lbs) => formatNumber(liftValue(lbs), 1);
  String formatLift(double lbs) => '${liftNumber(lbs)} $liftLabel';

  // --- Distance (stored in km).
  String get distanceLabel => distance.name;
  double distanceValue(double km) =>
      distance == DistanceUnit.km ? km : km / kmPerMile;
  double distanceToKm(double value) =>
      distance == DistanceUnit.km ? value : value * kmPerMile;
  String formatDistance(double km, {int decimals = 1}) =>
      '${formatNumber(distanceValue(km), decimals)} $distanceLabel';

  // --- Height (stored in cm).
  String formatHeight(double cm) {
    if (height == HeightUnit.cm) return '${cm.round()} cm';
    final (:feet, :inches) = feetInches(cm);
    return '$feet′ $inches″';
  }

  static ({int feet, int inches}) feetInches(double cm) {
    final total = (cm / cmPerInch).round();
    return (feet: total ~/ 12, inches: total % 12);
  }

  static double cmFromFeetInches(int feet, double inches) =>
      (feet * 12 + inches) * cmPerInch;

  @override
  bool operator ==(Object other) =>
      other is Units &&
      other.bodyWeight == bodyWeight &&
      other.liftWeight == liftWeight &&
      other.distance == distance &&
      other.height == height;

  @override
  int get hashCode => Object.hash(bodyWeight, liftWeight, distance, height);
}

/// "kg" or "lbs", as the app has always written pounds.
String _massLabel(MassUnit unit) => unit == MassUnit.kg ? 'kg' : 'lbs';

/// [value] with up to [decimals] places, trailing zeros dropped: 70.0 →
/// "70", 61.25 → "61.3".
String formatNumber(double value, int decimals) {
  final fixed = value.toStringAsFixed(decimals);
  if (!fixed.contains('.')) return fixed;
  return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
}
