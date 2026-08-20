enum HeartRateZone {
  low('Low', 'Under 60 bpm'),
  relaxed('Relaxed', '60–79 bpm'),
  raised('Raised', '80–99 bpm'),
  high('High', '100+ bpm');

  const HeartRateZone(this.label, this.rangeLabel);

  final String label;
  final String rangeLabel;
}

HeartRateZone heartRateZoneFor(double bpm) {
  if (bpm < 60) return HeartRateZone.low;
  if (bpm < 80) return HeartRateZone.relaxed;
  if (bpm < 100) return HeartRateZone.raised;
  return HeartRateZone.high;
}
