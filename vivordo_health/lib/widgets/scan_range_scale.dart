import 'package:flutter/material.dart';

/// Where a scanned heart rate sits: the same three plain bands the result
/// names, none of them a warning (80 to 100 is a normal resting rate).
enum HeartRateBand {
  resting('Resting'),
  typical('Typical'),
  higher('Higher');

  const HeartRateBand(this.label);

  final String label;

  static HeartRateBand of(int bpm) => bpm < 65
      ? resting
      : bpm < 80
      ? typical
      : higher;
}

/// The scale's ends, in bpm. Readings beyond them sit at the end.
const scanScaleLow = 40, scanScaleHigh = 120;

/// How far along the scale [bpm] is, 0 to 1.
double scanScaleFraction(int bpm) =>
    ((bpm - scanScaleLow) / (scanScaleHigh - scanScaleLow)).clamp(0.0, 1.0);

/// The reading on a Resting / Typical / Higher scale, for the purple result
/// card: three segments, the reading's own lit, and a marker where it falls.
class ScanRangeScale extends StatelessWidget {
  const ScanRangeScale({super.key, required this.bpm});

  final int bpm;

  // Where each band ends on the scale, as flex out of 80 bpm.
  static const _spans = [
    (HeartRateBand.resting, 25),
    (HeartRateBand.typical, 15),
    (HeartRateBand.higher, 40),
  ];

  @override
  Widget build(BuildContext context) {
    final band = HeartRateBand.of(bpm);
    return Semantics(
      label: '$bpm beats per minute, in the ${band.label} range',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 18,
            child: LayoutBuilder(
              builder: (context, constraints) => Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.centerLeft,
                children: [
                  Row(
                    children: [
                      for (final (index, (b, flex)) in _spans.indexed) ...[
                        if (index > 0) const SizedBox(width: 3),
                        Expanded(
                          flex: flex,
                          child: Container(
                            height: 6,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(
                                alpha: b == band ? .95 : .28,
                              ),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Positioned(
                    left: (constraints.maxWidth * scanScaleFraction(bpm) - 7)
                        .clamp(0.0, constraints.maxWidth - 14),
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.black.withValues(alpha: .18),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              for (final (index, (b, flex)) in _spans.indexed) ...[
                if (index > 0) const SizedBox(width: 3),
                Expanded(
                  flex: flex,
                  child: Text(
                    b.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: b == band ? 1 : .6),
                      fontSize: 11,
                      fontWeight: b == band ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
