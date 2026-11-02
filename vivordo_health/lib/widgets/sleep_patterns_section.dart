import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';

import '../src/utils/detail_insights.dart';
import 'apple_ui.dart';

/// Sleep detail's "Your patterns": the top three [patterns] (the rest
/// behind "Show more"), each opening a sheet with why it matters and one
/// thing to try. [onAction] runs a sheet's button.
class SleepPatternsSection extends StatefulWidget {
  const SleepPatternsSection({
    super.key,
    required this.patterns,
    required this.onAction,
  });

  final List<SleepPattern> patterns;
  final void Function(SleepPatternAction action) onAction;

  @override
  State<SleepPatternsSection> createState() => _SleepPatternsSectionState();
}

class _SleepPatternsSectionState extends State<SleepPatternsSection> {
  static const _shown = 3;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final patterns = widget.patterns;
    final hidden = _all ? 0 : patterns.length - _shown;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            const Expanded(
              child: Text(
                'Your patterns',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              ),
            ),
            Text(
              'Last few weeks',
              style: TextStyle(fontSize: 13, color: colors.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (final pattern in patterns.take(_all ? patterns.length : _shown))
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _PatternCard(
              pattern: pattern,
              onTap: pattern.why == null
                  ? null
                  : () => _showPattern(context, pattern, widget.onAction),
            ),
          ),
        if (hidden > 0)
          Center(
            child: TextButton(
              onPressed: () => setState(() => _all = true),
              child: Text(
                'Show $hidden more pattern${hidden == 1 ? '' : 's'}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
      ],
    );
  }
}

(IconData, Color) _style(BuildContext context, SleepPattern pattern) =>
    pattern.progress != null
    ? (CupertinoIcons.clock, context.vivordoColors.textSecondary)
    : insightStyle(pattern.tone);

Widget _bubble(IconData icon, Color color, double size) => Container(
  width: size,
  height: size,
  decoration: BoxDecoration(
    color: color.withValues(alpha: .12),
    shape: BoxShape.circle,
  ),
  child: Icon(icon, color: color, size: size * .5),
);

class _PatternCard extends StatelessWidget {
  const _PatternCard({required this.pattern, this.onTap});

  final SleepPattern pattern;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final (icon, color) = _style(context, pattern);
    return Material(
      color: colors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _bubble(icon, color, 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pattern.title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          pattern.body,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.4,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (onTap != null)
                    const Padding(
                      padding: EdgeInsets.only(left: 6, top: 2),
                      child: Icon(
                        CupertinoIcons.chevron_right,
                        size: 18,
                        color: VivordoTheme.brand,
                      ),
                    ),
                ],
              ),
              if (pattern.chart case final chart?)
                Padding(
                  padding: const EdgeInsets.only(left: 52, top: 12),
                  child: ExcludeSemantics(
                    child: SizedBox(
                      width: 200,
                      height: 36,
                      child: CustomPaint(
                        painter: _BarsPainter(chart, color, colors.border),
                      ),
                    ),
                  ),
                ),
              if (pattern.progress case final progress?)
                Padding(
                  padding: const EdgeInsets.only(left: 52, top: 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress.clamp(0, 1),
                      minHeight: 8,
                      color: VivordoTheme.brand,
                      backgroundColor: colors.cardMuted,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _showPattern(
  BuildContext context,
  SleepPattern pattern,
  void Function(SleepPatternAction action) onAction,
) => showAppleSheet<void>(
  context,
  builder: (sheetContext) {
    final colors = sheetContext.vivordoColors;
    final (icon, color) = _style(sheetContext, pattern);
    Widget section(String title, String text) => Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(text, style: const TextStyle(fontSize: 16, height: 1.45)),
        ],
      ),
    );
    final chart = pattern.chart;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * .85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppleGrabber(),
              const SizedBox(height: 12),
              Row(
                children: [
                  _bubble(icon, color, 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      pattern.title,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              if (chart != null) ...[
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
                  decoration: BoxDecoration(
                    color: colors.card,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: colors.border),
                  ),
                  child: Column(
                    children: [
                      ExcludeSemantics(
                        child: SizedBox(
                          height: 130,
                          width: double.infinity,
                          child: CustomPaint(
                            painter: _BarsPainter(
                              chart,
                              color,
                              colors.border,
                              line: colors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _labels(chart, colors.textSecondary),
                    ],
                  ),
                ),
              ],
              section('What Vivordo noticed', pattern.body),
              if (pattern.why case final why?) section('Why it matters', why),
              if (pattern.tryThis case final tryThis?)
                section('Try this', tryThis),
              if ((pattern.action, pattern.actionLabel) case (
                final action?,
                final label?,
              )) ...[
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: VivordoTheme.brand,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      onAction(action);
                    },
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Text(
                '${pattern.basis == null ? '' : '${pattern.basis} '}'
                'A wellness estimate, not medical advice.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  },
);

/// One label under each bar when every bar has one, else the ends.
Widget _labels(SleepPatternChart chart, Color color) {
  final style = TextStyle(fontSize: 11, color: color);
  if (chart.labels.every((l) => l.isNotEmpty)) {
    return Row(
      children: [
        for (final label in chart.labels)
          Expanded(
            child: Text(label, textAlign: TextAlign.center, style: style),
          ),
      ],
    );
  }
  return Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      for (final label in chart.labels)
        if (label.isNotEmpty) Text(label, style: style),
    ],
  );
}

/// The chart's bars, [highlight] colour for the highlighted ones, with a
/// dashed [line] at the reference when given.
class _BarsPainter extends CustomPainter {
  _BarsPainter(this.chart, this.highlight, this.base, {this.line});

  final SleepPatternChart chart;
  final Color highlight, base;
  final Color? line;

  @override
  void paint(Canvas canvas, Size size) {
    final values = chart.values;
    if (values.isEmpty) return;
    final top = [
      ...values.whereType<double>(),
      ?chart.reference,
    ].fold<double>(1, (a, b) => a > b ? a : b);
    final scale = size.height / (top * 1.1);
    final slot = size.width / values.length;
    final width = (slot * .6).clamp(4.0, 28.0);
    for (final (i, value) in values.indexed) {
      if (value == null) continue;
      final rect = Rect.fromLTWH(
        i * slot + (slot - width) / 2,
        size.height - value * scale,
        width,
        value * scale,
      );
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          rect,
          topLeft: Radius.circular(width / 2),
          topRight: Radius.circular(width / 2),
        ),
        Paint()..color = chart.highlight.contains(i) ? highlight : base,
      );
    }
    if ((chart.reference, line) case (final reference?, final color?)) {
      final y = size.height - reference * scale;
      final paint = Paint()
        ..color = color
        ..strokeWidth = 1;
      for (var x = 0.0; x < size.width; x += 8) {
        canvas.drawLine(Offset(x, y), Offset(x + 4, y), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.chart != chart || old.highlight != highlight || old.base != base;
}
