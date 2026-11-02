import 'dart:math' as math;

/// Complex number for FFT.
class Complex {
  final double real;
  final double imag;
  Complex(this.real, this.imag);

  Complex operator +(Complex o) => Complex(real + o.real, imag + o.imag);
  Complex operator -(Complex o) => Complex(real - o.real, imag - o.imag);
  Complex operator *(Complex o) => Complex(
      real * o.real - imag * o.imag, real * o.imag + imag * o.real);

  double get magnitude => math.sqrt(real * real + imag * imag);
}

/// PPG heart-rate algorithm.
///
/// ── RESEARCH SUMMARY ──────────────────────────────────────────────────────────
///
/// Camera choice (Frontiers Digital Health 2024 / JMIR mHealth 2017):
///   Contact-based fingertip PPG consistently outperforms non-contact methods.
///   On iPhone Pro the ultrawide lens (backCameras[2]) is physically the closest
///   of the three rear lenses to the LED flash module.  Proximity to the flash
///   dominates sensor quality for this use-case because it maximises the amount
///   of diffuse (pulsatile) light reaching the camera.  Use backCameras[2] with
///   the flash torched.  The wide (main) camera has a better sensor but sits
///   further from the flash, which produces a weaker AC component in the signal.
///
/// Root cause of the 40-BPM errors:
///   PPG waveforms are not pure sinusoids.  They contain strong 2nd and 3rd
///   harmonics (Maxim ADI spec sheet; KID-PPG, arXiv 2405.09559).  When the
///   2nd-harmonic (2×HR) has more spectral energy than the fundamental —
///   common with the dicrotic notch — a naive max-PSD search finds 2×HR instead
///   of HR.  When low-frequency noise or filter transients dominate, it finds
///   HR/2 instead (hence 40 BPM from an 80-BPM subject).  Both errors are
///   eliminated by harmonic scoring.
///
/// Key algorithm improvements over the previous version:
///
///   1. HARMONIC SCORING (primary fix).
///      For every candidate fundamental frequency f, compute:
///        score(f) = PSD(f) + 0.5·PSD(2f) + 0.25·PSD(3f)
///      A true cardiac fundamental always has harmonic support; a sub-harmonic
///      artefact at f/2 does not have strong energy at f and 2f, so its score
///      is low even if PSD(f/2) momentarily dominates (IEEE HSUM paper, 2018;
///      Analog Devices MUSIC paper).
///
///   2. MULTI-WINDOW PROCESSING + ROBUST MEDIAN.
///      The recording is sliced into 8-second windows stepped every 2 s.
///      Each window yields an independent BPM estimate; the final answer is the
///      median after outlier rejection.  This makes a single noisy segment unable
///      to corrupt the result (approach validated in Dubey et al. 2018 and
///      Charlton et al. 2022 benchmarking study).
///
///   3. PER-WINDOW SNR GATE.
///      A window whose cardiac-band signal-to-noise ratio (AC power at f±1 bins
///      vs total band power) is below a threshold is discarded before it reaches
///      the median pool.  This is the same definition used by Maxim Integrated's
///      production PPG algorithm (power at fundamental + harmonics / noise power).
///
///   4. ZERO-PHASE BANDPASS.
///      2nd-order Butterworth bandpass (0.5–4.0 Hz = 30–240 BPM) run forwards
///      and backwards.  Reflection padding in filtfilt removes edge transients.
///
///   5. RETAINED from previous version:
///      linear detrend, std-dev normalisation, reflection-padded filtfilt,
///      parabolic sub-bin interpolation.
///
class PpgAlgorithm {
  // ── Constants ──────────────────────────────────────────────────────────────
  static const double _fs     = 30.0;   // target sample rate (Hz)
  static const double _minBpm = 45.0;   // minimum physiological HR
  static const double _maxBpm = 180.0;  // maximum physiological HR
  static const double _maxPeakBpm = 160.0; // fastest beat gap peakBpm counts

  // ── Filter coefficients ────────────────────────────────────────────────────
  //
  // 0.5 – 4.0 Hz 2nd-order Butterworth bandpass at 30 Hz.  Run forwards and
  // backwards by _filtfilt, so the effective order doubles with zero phase.
  // (A second "0.6 – 3.5 Hz" section used to follow; its poles sat outside the
  // unit circle, so it blew up every signal and the FFT never read a pulse.)
  static final List<double> _bBp = [ 0.08942, 0.0, -0.17884, 0.0,  0.08942];
  static final List<double> _aBp = [ 1.0, -2.86538, 3.14923, -1.63388, 0.35504];

  // ── Public API ────────────────────────────────────────────────────────────

  /// Scans scoring below this are too unreliable to save.
  static const double minQuality = 0.5;

  /// The scan's heart rate from [raw] pixel intensities at [times] (seconds),
  /// with both estimates behind it for logging.  Beat gaps ([peakBpm]) are the
  /// finer measure, but a second bump in each beat can double them up.  When
  /// they disagree with the FFT ([calculateBPM]) by over 10%, the gaps still
  /// win if they're steady, or if the FFT sits at 2× or 3× them (it locked
  /// onto a harmonic; missing every other beat is far rarer).  Otherwise
  /// the FFT wins.
  /// bpm is 0.0 when neither finds a pulse.
  ///
  /// quality (0–1) is how far to trust it: how clearly the beat stands out,
  /// whether the FFT's windows agree with each other (a finger shift throws
  /// one off by tens of BPM), and whether both methods agree.  Beat
  /// regularity is left out: an irregular rhythm would look like a bad scan.
  static ({double bpm, double fftBpm, double peakBpm, double quality})
      heartRate(List<double> raw, List<double> times) {
    final List<double>? xf = _prepare(raw, times);
    if (xf == null) {
      return (bpm: 0.0, fftBpm: 0.0, peakBpm: 0.0, quality: 0.0);
    }
    final List<double> windows = _multiWindowEstimates(xf);
    final double fft  = windows.isEmpty ? 0.0 : _robustMedian(windows);
    final ({double bpm, double cv}) beats = _peakBpm(xf);
    final double peak = beats.bpm;
    final bool agree  =
        peak > 0 && (fft == 0 || (peak - fft).abs() <= 0.1 * fft);
    final bool steadyBeats = peak > 0 && beats.cv < 0.1;
    final bool fftOnHarmonic = peak > 0 &&
        [2, 3].any((k) => (fft - k * peak).abs() <= 0.1 * k * peak);

    // ponytail: weights and ranges tuned on synthetic scans only; retune
    // against WHOOP readings once real [PPG] logs exist.
    final double clear =
        ((_peakShare(_powerSpectrum(xf)) - 0.25) / 0.30).clamp(0.0, 1.0);
    final double spread = windows.length < 2
        ? double.infinity
        : windows.reduce(math.max) - windows.reduce(math.min);
    final double steady = (1.0 - (spread - 3.0) / 12.0).clamp(0.0, 1.0);
    final bool bothAgree = agree && fft > 0;
    final double quality =
        0.4 * clear + 0.4 * steady + (bothAgree ? 0.2 : 0.0);

    return (
      bpm: agree || steadyBeats || fftOnHarmonic ? peak : fft,
      fftBpm: fft,
      peakBpm: peak,
      quality: quality,
    );
  }

  /// Returns heart rate in BPM from [raw] pixel intensities, each sampled at
  /// [times] (seconds, the frame's real arrival time).  Returns 0.0 if the
  /// signal is too short or low quality.
  static double calculateBPM(List<double> raw, List<double> times) {
    final List<double>? xf = _prepare(raw, times);
    if (xf == null) return 0.0;

    // Multi-window BPM estimates, then a robust median with outlier rejection
    final List<double> estimates = _multiWindowEstimates(xf);
    if (estimates.isEmpty) return 0.0;
    return _robustMedian(estimates);
  }

  /// Heart rate from the gaps between beats in the filtered pulse.  Finer than
  /// the FFT's bins, but a second bump in each beat can still fool it, so
  /// [heartRate] cross-checks it against [calculateBPM].  Returns 0.0 if too
  /// few beats are found.
  static double peakBpm(List<double> raw, List<double> times) {
    final List<double>? xf = _prepare(raw, times);
    return xf == null ? 0.0 : _peakBpm(xf).bpm;
  }

  /// [peakBpm] plus the coefficient of variation of the beat gaps.
  static ({double bpm, double cv}) _peakBpm(List<double> xf) {
    const none = (bpm: 0.0, cv: double.infinity);
    final double threshold = 0.5 * _stdDev(xf);
    final int minGap = (_fs * 60.0 / _maxPeakBpm).round();
    final List<int> peaks = [];
    for (int i = 1; i < xf.length - 1; i++) {
      if (xf[i] <= xf[i - 1] || xf[i] < xf[i + 1] || xf[i] < threshold) {
        continue;
      }
      if (peaks.isNotEmpty && i - peaks.last < minGap) {
        // Too close to be a new beat: keep whichever bump is taller.
        if (xf[i] > xf[peaks.last]) peaks[peaks.length - 1] = i;
      } else {
        peaks.add(i);
      }
    }

    // Parabolic sub-sample peak positions, so gaps aren't rounded to 33 ms.
    final List<double> pos = peaks.map((i) {
      final double denom = xf[i - 1] - 2.0 * xf[i] + xf[i + 1];
      final double offset =
          denom.abs() > 1e-12 ? 0.5 * (xf[i - 1] - xf[i + 1]) / denom : 0.0;
      return i + offset.clamp(-0.5, 0.5);
    }).toList();

    final double minInterval = 60.0 / _maxPeakBpm;
    final double maxInterval = 60.0 / _minBpm;
    final List<double> intervals = [];
    for (int i = 1; i < pos.length; i++) {
      final double gap = (pos[i] - pos[i - 1]) / _fs;
      if (gap >= minInterval && gap <= maxInterval) intervals.add(gap);
    }
    if (intervals.length < 4) return none;

    // Mean of the gaps near the median: steadier than the median alone.
    intervals.sort();
    final double med = intervals[intervals.length ~/ 2];
    final List<double> near =
        intervals.where((g) => (g - med).abs() <= 0.2 * med).toList();
    final double mean = near.reduce((a, b) => a + b) / near.length;
    final double bpm = 60.0 / mean;
    if (bpm < _minBpm || bpm > _maxPeakBpm) return none;

    final double all = intervals.reduce((a, b) => a + b) / intervals.length;
    final double sd = math.sqrt(
        intervals.map((g) => (g - all) * (g - all)).reduce((a, b) => a + b) /
            intervals.length);
    return (bpm: bpm, cv: sd / all);
  }

  /// How clearly a heartbeat stands out in [raw], 0–1: the share of
  /// cardiac-band power at the strongest peak.  Used to pick the cleaner
  /// colour channel.
  static double clarity(List<double> raw, List<double> times) {
    final List<double>? xf = _prepare(raw, times);
    if (xf == null) return 0.0;
    return _peakShare(_powerSpectrum(xf));
  }

  /// Resamples [raw] onto an even 30 Hz grid using the real sample [times],
  /// then detrends, normalises and bandpasses it.  Null when the signal is
  /// too short or flat.
  static List<double>? _prepare(List<double> raw, List<double> times) {
    if (raw.length < 50 || raw.length != times.length) return null;
    final double span = times.last - times.first;
    if (span <= 0) return null;

    // 1. Resample to 30 Hz on the frames' real timestamps; frames don't
    //    arrive evenly, and some are dropped.
    final List<double> x = _resample(raw, times, (span * _fs).floor() + 1);

    // 2. Linear detrend removes DC offset and any slow ramp
    final List<double> xd = _linearDetrend(x);

    // 3. Std-dev quality gate + normalise
    final double sigma = _stdDev(xd);
    if (sigma < 1e-6) return null; // flat signal → no finger on lens
    final List<double> xn = xd.map((v) => v / sigma).toList();

    // 4. Zero-phase bandpass
    return _filtfilt(_bBp, _aBp, xn);
  }

  // ── Multi-window processing ───────────────────────────────────────────────

  /// Slices [signal] into overlapping 8-second windows and returns a BPM
  /// estimate for each window that passes the SNR gate.
  static List<double> _multiWindowEstimates(List<double> signal) {
    final int winLen  = math.min((8 * _fs).round(), signal.length);
    // 2 s steps: a 13 s scan gives 3 windows, so the median can outvote one
    // noisy stretch (4 s steps gave only 2).
    final int step    = math.max((2 * _fs).round(), 1);

    final List<double> out = [];

    for (int start = 0; start + winLen <= signal.length; start += step) {
      final List<double> seg = signal.sublist(start, start + winLen);
      final double bpm = _segmentBpm(seg);
      if (bpm >= _minBpm && bpm <= _maxBpm) out.add(bpm);
    }

    // Fallback: use full signal if too short for even one full window
    if (out.isEmpty && signal.length >= 64) {
      final double bpm = _segmentBpm(signal);
      if (bpm >= _minBpm && bpm <= _maxBpm) out.add(bpm);
    }

    return out;
  }

  /// Computes a BPM estimate for a single [segment] using a Hann-windowed FFT
  /// and harmonic scoring.  Returns 0 if the segment fails the SNR gate.
  static double _segmentBpm(List<double> segment) {
    final List<double> psd = _powerSpectrum(segment);

    // SNR gate: ratio of cardiac-band peak power to total band power
    if (_peakShare(psd) <= 0.15) return 0.0; // need 15% of band energy at the peak

    return _harmonicBpm(psd, (psd.length - 1) * 2);
  }

  /// One-sided power spectrum (magnitude squared) of a Hann-windowed FFT.
  static List<double> _powerSpectrum(List<double> segment) {
    final int n    = segment.length;
    final int nfft = _nextPow2(math.max(n, 512));

    // Hann window (using N-1 denominator for a proper symmetric window)
    final List<double> win = List.generate(
        n, (i) => 0.5 * (1.0 - math.cos(2.0 * math.pi * i / (n - 1))));

    final List<Complex> fftIn = List.generate(nfft, (i) {
      if (i < n) return Complex(segment[i] * win[i], 0.0);
      return Complex(0.0, 0.0);
    });

    final List<Complex> fftOut = _fft(fftIn);
    final int nBins = nfft ~/ 2 + 1;

    return List.generate(nBins, (k) {
      final double m = fftOut[k].magnitude;
      return m * m;
    });
  }

  // ── Harmonic scoring ──────────────────────────────────────────────────────

  /// For each candidate fundamental bin k in [_minBpm, _maxBpm] compute:
  ///   score(k) = PSD(k) + 0.5·PSD(2k) + 0.25·PSD(3k)
  ///
  /// This is the core fix for the 40-BPM problem.  A sub-harmonic artefact
  /// at f/2 cannot score well because its "harmonics" at f and 3f/2 are weak.
  /// A true cardiac fundamental always has energy at 2f and 3f.
  static double _harmonicBpm(List<double> psd, int nfft) {
    final double res  = _fs / nfft; // Hz per bin
    final int nBins   = psd.length;

    final int kMin = (_minBpm / 60.0 / res).ceil().clamp(1, nBins - 2);
    final int kMax = (_maxBpm / 60.0 / res).floor().clamp(1, nBins - 2);
    if (kMin >= kMax) return 0.0;

    double bestScore = -double.maxFinite;
    int bestK = kMin;

    for (int k = kMin; k <= kMax; k++) {
      double score = psd[k];
      final int k2 = k * 2;
      final int k3 = k * 3;
      if (k2 < nBins) score += 0.5  * psd[k2];
      if (k3 < nBins) score += 0.25 * psd[k3];
      if (score > bestScore) {
        bestScore = score;
        bestK    = k;
      }
    }

    // A strong second bump in each beat can put more power at 2× or 3×HR
    // than at HR itself.  Real power at a third or half of the winner means
    // that's the beat, if that candidate's other harmonic (3× for a half,
    // 2× for a third) shows too: a finger shift makes the filter ring near
    // 45–60 BPM, which has power there but no harmonics.
    for (final int d in [3, 2]) {
      final int sub = (bestK / d).round();
      if (sub - 1 < kMin) continue;
      int sk = sub;
      if (psd[sub - 1] > psd[sk]) sk = sub - 1;
      if (psd[sub + 1] > psd[sk]) sk = sub + 1;
      final int other = sk * (d == 2 ? 3 : 2);
      double otherPow = 0.0;
      for (int o = other - 1; o <= other + 1 && o < nBins; o++) {
        otherPow = math.max(otherPow, psd[o]);
      }
      if (psd[sk] > 0.2 * psd[bestK] && otherPow > 0.06 * psd[bestK]) {
        bestK = sk;
        break;
      }
    }

    // Parabolic sub-bin interpolation on the raw PSD (not the score)
    // to find the true spectral peak with better frequency resolution.
    double peakFreq;
    if (bestK > 0 && bestK < nBins - 1) {
      final double pLeft   = psd[bestK - 1];
      final double pCenter = psd[bestK];
      final double pRight  = psd[bestK + 1];
      final double denom   = pLeft - 2.0 * pCenter + pRight;
      final double offset  = denom.abs() > 1e-12 ? 0.5 * (pLeft - pRight) / denom : 0.0;
      peakFreq = (bestK + offset.clamp(-0.5, 0.5)) * res;
    } else {
      peakFreq = bestK * res;
    }

    return peakFreq * 60.0;
  }

  // ── SNR gate ──────────────────────────────────────────────────────────────

  /// Share of cardiac-band power at the dominant peak; a low share is a
  /// sign of a poor contact or motion artefact.
  ///
  /// Following Maxim Integrated's definition: signal power = power at the
  /// dominant peak ± 2 bins; noise power = remaining band power.
  static double _peakShare(List<double> psd) {
    final int nBins   = psd.length;
    final double res  = _fs / ((nBins - 1) * 2);

    final int kMin = (_minBpm / 60.0 / res).ceil().clamp(0, nBins - 1);
    final int kMax = (_maxBpm / 60.0 / res).floor().clamp(0, nBins - 1);

    // Find peak bin in physiological range
    double peakPow = 0.0;
    int peakK = kMin;
    for (int k = kMin; k <= kMax; k++) {
      if (psd[k] > peakPow) { peakPow = psd[k]; peakK = k; }
    }

    // Signal power: ±2 bins around peak
    double sigPow  = 0.0;
    double totPow  = 0.0;
    for (int k = kMin; k <= kMax; k++) {
      totPow += psd[k];
      if ((k - peakK).abs() <= 2) sigPow += psd[k];
    }

    if (totPow < 1e-12) return 0.0;
    return sigPow / totPow;
  }

  // ── Robust median ─────────────────────────────────────────────────────────

  /// Median of [values] after removing entries > 20 BPM from the raw median.
  static double _robustMedian(List<double> values) {
    if (values.isEmpty) return 0.0;
    final List<double> s = List.from(values)..sort();
    final double med = s[s.length ~/ 2];
    final List<double> filtered = s.where((v) => (v - med).abs() <= 20.0).toList();
    if (filtered.isEmpty) return med;
    filtered.sort();
    return filtered[filtered.length ~/ 2];
  }

  // ── Signal conditioning helpers ───────────────────────────────────────────

  static List<double> _resample(
      List<double> raw, List<double> times, int nTarget) {
    final List<double> out = [];
    int j = 0;
    for (int i = 0; i < nTarget; i++) {
      final double t = times.first + i / _fs;
      while (j < times.length - 2 && times[j + 1] < t) {
        j++;
      }
      final double dt = times[j + 1] - times[j];
      final double w = dt > 0 ? ((t - times[j]) / dt).clamp(0.0, 1.0) : 0.0;
      out.add(raw[j] * (1.0 - w) + raw[j + 1] * w);
    }
    return out;
  }

  static List<double> _linearDetrend(List<double> x) {
    final int n = x.length;
    double st = 0, sx = 0, stx = 0, st2 = 0;
    for (int i = 0; i < n; i++) {
      st  += i.toDouble();
      sx  += x[i];
      stx += i * x[i];
      st2 += i * i.toDouble();
    }
    final double d = n * st2 - st * st;
    if (d.abs() < 1e-12) {
      final double m = sx / n;
      return x.map((v) => v - m).toList();
    }
    final double slope = (n * stx - st * sx) / d;
    final double bias  = (sx - slope * st) / n;
    return List.generate(n, (i) => x[i] - (slope * i + bias));
  }

  static double _stdDev(List<double> x) {
    if (x.isEmpty) return 0.0;
    final double m = x.reduce((a, b) => a + b) / x.length;
    return math.sqrt(
        x.map((v) => (v - m) * (v - m)).reduce((a, b) => a + b) / x.length);
  }

  // ── Zero-phase IIR filter with reflection padding ─────────────────────────

  static List<double> _filtfilt(
      List<double> b, List<double> a, List<double> x) {
    final int order  = math.max(a.length, b.length) - 1;
    final int padLen = (3 * order).clamp(1, x.length - 1);

    final List<double> padded = [];
    for (int i = padLen; i > 0; i--) {
      padded.add(2.0 * x.first - x[i.clamp(0, x.length - 1)]);
    }
    padded.addAll(x);
    for (int i = 1; i <= padLen; i++) {
      padded.add(2.0 * x.last -
          x[(x.length - 1 - i).clamp(0, x.length - 1)]);
    }

    final List<double> fwd = _filter(b, a, padded);
    final List<double> bwd =
        _filter(b, a, fwd.reversed.toList()).reversed.toList();

    return bwd.sublist(padLen, padLen + x.length);
  }

  static List<double> _filter(
      List<double> b, List<double> a, List<double> x) {
    final int n    = x.length;
    final int mLen = math.max(a.length, b.length);
    final List<double> y = List.filled(n, 0.0);
    final List<double> z = List.filled(mLen, 0.0);
    for (int i = 0; i < n; i++) {
      y[i] = b[0] * x[i] + z[0];
      for (int j = 1; j < mLen; j++) {
        final double bj = j < b.length ? b[j] : 0.0;
        final double aj = j < a.length ? a[j] : 0.0;
        z[j - 1] = bj * x[i] - aj * y[i] + (j + 1 < mLen ? z[j] : 0.0);
      }
    }
    return y;
  }

  // ── Cooley-Tukey Radix-2 FFT ──────────────────────────────────────────────

  static List<Complex> _fft(List<Complex> x) {
    final int n = x.length;
    if (n <= 1) return x;
    final List<Complex> even = _fft(List.generate(n ~/ 2, (i) => x[i * 2]));
    final List<Complex> odd  = _fft(List.generate(n ~/ 2, (i) => x[i * 2 + 1]));
    final List<Complex> t = List.generate(n ~/ 2, (k) {
      final double ang = -2.0 * math.pi * k / n;
      return Complex(math.cos(ang), math.sin(ang)) * odd[k];
    });
    final List<Complex> res = List.filled(n, Complex(0.0, 0.0));
    for (int k = 0; k < n ~/ 2; k++) {
      res[k]          = even[k] + t[k];
      res[k + n ~/ 2] = even[k] - t[k];
    }
    return res;
  }

  static int _nextPow2(int n) {
    int p = 1;
    while (p < n) {
      p <<= 1;
    }
    return p;
  }
}
