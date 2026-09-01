enum HomeStressDriverType { sleep, heartRate, hrv, activity, mood, other }

class HomeStressDriver {
  const HomeStressDriver({required this.label, required this.type});

  final String label;
  final HomeStressDriverType type;
}

List<HomeStressDriver> homeStressDrivers(Object? raw, {int limit = 2}) {
  if (raw is! List || limit <= 0) return const [];
  final drivers = <HomeStressDriver>[];

  for (final item in raw) {
    String? name;
    String? detail;
    double? influence;

    if (item is String) {
      name = item;
    } else if (item is Map) {
      name = _firstString(item, const [
        'label',
        'name',
        'signal',
        'metric',
        'driver',
        'feature',
      ]);
      detail = _firstString(item, const [
        'status',
        'direction',
        'effect',
        'detail',
        'reason',
      ]);
      influence = _firstNumber(item, const [
        'percentage',
        'percent',
        'weight',
        'contribution',
        'influence',
      ]);
    }

    if (name == null || name.trim().isEmpty) continue;
    final type = _driverType(name);
    drivers.add(
      HomeStressDriver(
        label: _driverLabel(name, detail, influence, type),
        type: type,
      ),
    );
    if (drivers.length == limit) break;
  }

  return drivers;
}

String homeStressRangeMessage(double? score, double? sevenDayAverage) {
  if (score == null) return 'Your stress score will appear as data comes in.';
  if (sevenDayAverage != null) {
    final difference = score - sevenDayAverage;
    if (difference <= -2) return 'Your stress is below your usual range.';
    if (difference >= 2) return 'Your stress is above your usual range.';
    return 'Your stress is within your usual range.';
  }
  if (score < 30) return 'Your current stress is low.';
  if (score < 60) return 'Your current stress is manageable.';
  if (score < 80) return 'Your current stress is elevated.';
  return 'Your current stress is high.';
}

String homeStressComparison(double? score, double? sevenDayAverage) {
  if (score == null || sevenDayAverage == null) {
    return 'Building your 7-day baseline.';
  }
  final difference = (score - sevenDayAverage).round();
  if (difference == 0) return 'In line with your 7-day average.';
  return '${difference.abs()} point${difference.abs() == 1 ? '' : 's'} '
      '${difference < 0 ? 'below' : 'above'} your 7-day average.';
}

String homeStressAction({
  required double? score,
  required List<HomeStressDriver> drivers,
  required int steps,
}) {
  final types = drivers.map((driver) => driver.type).toSet();
  if (types.contains(HomeStressDriverType.sleep)) {
    final sleep = drivers.firstWhere(
      (driver) => driver.type == HomeStressDriverType.sleep,
    );
    if (sleep.label.toLowerCase().contains('short') ||
        sleep.label.toLowerCase().contains('poor')) {
      return 'A lighter day and an earlier bedtime may support recovery.';
    }
  }
  if (types.contains(HomeStressDriverType.heartRate) ||
      types.contains(HomeStressDriverType.hrv)) {
    if ((score ?? 0) >= 60) {
      return 'Try a few minutes of slow breathing to help your body settle.';
    }
  }
  if (steps < 3000 && (score ?? 0) < 80) {
    return 'A short walk may help keep stress down.';
  }
  if ((score ?? 0) >= 80) {
    return 'Pause, recover, and keep your next activity gentle.';
  }
  if ((score ?? 0) >= 60) {
    return 'A brief reset may help prevent stress from building.';
  }
  return 'Keep your routine steady to support a balanced day.';
}

String? _firstString(Map item, List<String> keys) {
  for (final key in keys) {
    final value = item[key];
    if (value != null && value.toString().trim().isNotEmpty) {
      return value.toString().trim();
    }
  }
  return null;
}

double? _firstNumber(Map item, List<String> keys) {
  for (final key in keys) {
    final value = item[key];
    if (value is num) return value.toDouble();
  }
  return null;
}

HomeStressDriverType _driverType(String name) {
  final normalized = name.toLowerCase().replaceAll('_', ' ');
  if (normalized.contains('sleep')) return HomeStressDriverType.sleep;
  if (normalized.contains('hrv') ||
      normalized.contains('heart rate variability')) {
    return HomeStressDriverType.hrv;
  }
  if (normalized.contains('heart rate') ||
      normalized.contains('resting heart') ||
      normalized == 'hr') {
    return HomeStressDriverType.heartRate;
  }
  if (normalized.contains('step') ||
      normalized.contains('activity') ||
      normalized.contains('exercise')) {
    return HomeStressDriverType.activity;
  }
  if (normalized.contains('mood')) return HomeStressDriverType.mood;
  return HomeStressDriverType.other;
}

String _driverLabel(
  String name,
  String? detail,
  double? influence,
  HomeStressDriverType type,
) {
  final context = '${detail ?? ''} $name'.toLowerCase();
  switch (type) {
    case HomeStressDriverType.sleep:
      if (_containsAny(context, const ['short', 'poor', 'low', 'less'])) {
        return 'Short sleep';
      }
      if (_containsAny(context, const ['better', 'good', 'long', 'restful'])) {
        return 'Better sleep';
      }
      if (influence != null) {
        return influence <= 0 ? 'Better sleep' : 'Sleep';
      }
      return 'Sleep';
    case HomeStressDriverType.heartRate:
      if (_containsAny(context, const ['elevated', 'high', 'higher'])) {
        return 'Elevated heart rate';
      }
      if (_containsAny(context, const ['stable', 'low', 'lower'])) {
        return 'Stable heart rate';
      }
      return 'Heart rate';
    case HomeStressDriverType.hrv:
      if (_containsAny(context, const ['low', 'lower', 'reduced'])) {
        return 'Lower HRV';
      }
      if (_containsAny(context, const ['high', 'higher', 'improved'])) {
        return 'Higher HRV';
      }
      return 'HRV';
    case HomeStressDriverType.activity:
      if (_containsAny(context, const ['low', 'less', 'sedentary'])) {
        return 'Low activity';
      }
      if (_containsAny(context, const ['active', 'higher', 'exercise'])) {
        return 'Recent activity';
      }
      return 'Daily activity';
    case HomeStressDriverType.mood:
      return 'Mood check-in';
    case HomeStressDriverType.other:
      return _title(name);
  }
}

bool _containsAny(String value, List<String> terms) =>
    terms.any(value.contains);

String _title(String value) => value
    .replaceAll('_', ' ')
    .split(RegExp(r'\s+'))
    .where((part) => part.isNotEmpty)
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join(' ');
