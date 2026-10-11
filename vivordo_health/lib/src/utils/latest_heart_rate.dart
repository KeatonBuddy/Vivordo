class LatestHeartRateReading {
  const LatestHeartRateReading({
    required this.bpm,
    this.timestamp,
    this.source,
  });

  final int bpm;
  final DateTime? timestamp;
  final String? source;
}
