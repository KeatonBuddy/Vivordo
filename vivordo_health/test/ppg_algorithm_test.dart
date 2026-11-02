import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/ppg_algorithm.dart';

/// A fingertip pulse at [bpm]: a sharp systolic peak, a smaller second bump
/// 0.35 s later, slow drift from pressure and torch warm-up, and camera noise.
/// Sampled at jittery frame times around [fps] with some frames dropped.
/// [jolts] adds finger shifts: (time, size) brightness jumps that settle.
({List<double> values, List<double> times}) _scan(
  double bpm, {
  double fps = 30,
  int seed = 1,
  double amplitude = 4,
  List<(double, double)> jolts = const [],
}) {
  final rng = math.Random(seed);
  final period = 60.0 / bpm;
  double pulse(double t) {
    final phase = t % period;
    double bump(double at, double width) =>
        math.exp(-math.pow((phase - at) / width, 2));
    return bump(0.12, 0.08) + 0.45 * bump(0.47, 0.07);
  }

  final values = <double>[];
  final times = <double>[];
  for (double t = 2.0; t < 15.0; t += 1 / fps) {
    if (rng.nextDouble() < 0.05) continue; // dropped frame
    final at = t + (rng.nextDouble() - 0.5) * 0.008; // arrival jitter
    var drift = 3.0 * at / 15 + 1.5 * math.sin(2 * math.pi * 0.1 * at);
    for (final (start, size) in jolts) {
      if (at > start) drift += size * math.exp(-(at - start) / 0.6);
    }
    final noise = (rng.nextDouble() - 0.5) * 0.8;
    values.add(200 + amplitude * pulse(at) + drift + noise);
    times.add(at);
  }
  return (values: values, times: times);
}

void main() {
  for (final bpm in [52.0, 72.0, 95.0]) {
    test('reads $bpm BPM through drift, a second bump and uneven frames', () {
      final s = _scan(bpm);
      expect(PpgAlgorithm.calculateBPM(s.values, s.times), closeTo(bpm, 2.5));
      expect(PpgAlgorithm.heartRate(s.values, s.times).bpm, closeTo(bpm, 2.5));
    });
  }

  test('uses real frame times, so a slower camera reads the same', () {
    final s = _scan(72, fps: 24, seed: 3);
    expect(PpgAlgorithm.peakBpm(s.values, s.times), closeTo(72, 0.5));
  });

  for (final bpm in [95.0, 110.0, 125.0]) {
    test('finger shifts at $bpm BPM don\'t halve the reading', () {
      final s = _scan(bpm, jolts: const [(4.5, 14), (8.5, -12), (12.0, 10)]);
      expect(PpgAlgorithm.heartRate(s.values, s.times).bpm, closeTo(bpm, 3));
    });
  }

  test('a clean scan passes the quality cut-off; no pulse mostly fails', () {
    final clean = _scan(72);
    expect(
      PpgAlgorithm.heartRate(clean.values, clean.times).quality,
      greaterThan(0.75),
    );
    var kept = 0;
    for (var seed = 0; seed < 40; seed++) {
      final flat = _scan(72, seed: seed, amplitude: 0);
      final r = PpgAlgorithm.heartRate(flat.values, flat.times);
      if (r.quality >= PpgAlgorithm.minQuality) kept++;
    }
    expect(kept, lessThanOrEqualTo(4));
  });

  test('a clean pulse is clearer than noise', () {
    final s = _scan(72);
    final rng = math.Random(9);
    final noise = [for (final _ in s.times) 200 + rng.nextDouble() * 4];
    expect(
      PpgAlgorithm.clarity(s.values, s.times),
      greaterThan(PpgAlgorithm.clarity(noise, s.times) * 2),
    );
  });
}
