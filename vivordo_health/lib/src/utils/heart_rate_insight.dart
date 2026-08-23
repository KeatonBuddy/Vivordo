class HeartRateInsightReading {
  const HeartRateInsightReading({required this.bpm, required this.timestamp});

  final double bpm;
  final DateTime timestamp;
}

String buildHeartRateInsight({
  required bool isDay,
  required List<HeartRateInsightReading> readings,
  required double? heartHealthScore,
  required double? restingAverage,
  required int? restingChange,
}) {
  if (!isDay) {
    return _buildPeriodInsight(restingAverage, restingChange);
  }

  final current =
      readings
          .where((reading) => reading.bpm.isFinite && reading.bpm > 0)
          .toList()
        ..sort((first, second) => first.timestamp.compareTo(second.timestamp));
  if (current.isEmpty) {
    return 'No readings yet today. Keep your wearable connected or take a scan.';
  }
  if (current.length < 5) {
    return 'More readings are needed for today’s trend. Keep your wearable connected.';
  }

  final average = _average(current);
  final recentChange = _recentDirection(current);
  final highShare = _share(current, (reading) => reading.bpm >= 100);
  final raisedShare = _share(
    current,
    (reading) => reading.bpm >= 80 && reading.bpm < 100,
  );
  final lowShare = _share(current, (reading) => reading.bpm < 60);
  final relaxedShare = _share(
    current,
    (reading) => reading.bpm >= 60 && reading.bpm < 80,
  );

  if (heartHealthScore != null && heartHealthScore < 40) {
    return 'Your Heart Health score is low today. Keep activity light and prioritize rest.';
  }
  if (heartHealthScore != null && heartHealthScore < 70) {
    return 'Your Heart Health score is below target today. Take recovery breaks and avoid pushing too hard.';
  }
  if (recentChange >= 10) {
    return 'Your recent heart rate is trending up. Slow down and take a short recovery break.';
  }
  if (recentChange <= -10) {
    return 'Your heart rate is settling after earlier readings. Keep recovery easy for now.';
  }
  if (average >= 100 || highShare >= 0.20) {
    return 'Your readings ran high today. Reduce intensity and give yourself time to recover.';
  }
  if (raisedShare >= 0.50) {
    return 'Most readings were raised today. Add a short rest period and check the trend later.';
  }
  if (lowShare >= 0.50) {
    return 'Most readings stayed low today. If you feel well, gentle activity can help you stay moving.';
  }
  if (relaxedShare >= 0.60) {
    return heartHealthScore != null && heartHealthScore >= 80
        ? 'Your heart pattern looks balanced today. Keep up your normal activity and recovery routine.'
        : 'Most readings were relaxed today. Keep a steady balance of movement and recovery.';
  }
  if (_range(current) >= 35) {
    return 'Your readings varied throughout the day. Balance active periods with short recovery breaks.';
  }
  if (heartHealthScore != null && heartHealthScore >= 80) {
    return 'Your Heart Health score is strong today. Keep up your normal activity and recovery routine.';
  }
  return 'Your heart-rate trend looks mixed but steady. Keep activity comfortable and allow time to recover.';
}

String _buildPeriodInsight(double? restingAverage, int? restingChange) {
  if (restingAverage == null) {
    return 'Complete a heart scan to begin building your heart rate trend.';
  }
  if (restingChange == null) {
    return 'Your resting heart rate averaged ${restingAverage.round()} bpm.';
  }
  if (restingChange <= 0) {
    return 'Your resting heart rate improved by ${restingChange.abs()} bpm.';
  }
  return 'Your resting heart rate increased by $restingChange bpm.';
}

double _average(List<HeartRateInsightReading> readings) {
  return readings.fold<double>(0, (sum, reading) => sum + reading.bpm) /
      readings.length;
}

double _share(
  List<HeartRateInsightReading> readings,
  bool Function(HeartRateInsightReading reading) qualifies,
) {
  return readings.where(qualifies).length / readings.length;
}

double _range(List<HeartRateInsightReading> readings) {
  var low = readings.first.bpm;
  var high = readings.first.bpm;
  for (final reading in readings.skip(1)) {
    if (reading.bpm < low) low = reading.bpm;
    if (reading.bpm > high) high = reading.bpm;
  }
  return high - low;
}

double _recentDirection(List<HeartRateInsightReading> readings) {
  if (readings.length < 8 ||
      readings.last.timestamp.difference(readings.first.timestamp) <
          const Duration(minutes: 30)) {
    return 0;
  }
  final groupSize = readings.length ~/ 3;
  final earlier = readings.take(groupSize).toList();
  final recent = readings.skip(readings.length - groupSize).toList();
  return _average(recent) - _average(earlier);
}
