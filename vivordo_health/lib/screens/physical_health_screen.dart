import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';

import '../src/utils/day_key.dart';
import '../src/utils/physical_health_view.dart';
import '../widgets/apple_ui.dart';
import '../widgets/visible_stream_builder.dart';

const _green = Color(0xFF1D9E75);
const _amber = Color(0xFFFF9500);
const _red = Color(0xFFE91F3D);
const _purple = Color(0xFF7F77DD);

Color physicalHealthColor(BuildContext context, double? value) => value == null
    ? context.vivordoColors.textSecondary
    : value >= 70
    ? _green
    : value >= 50
    ? _amber
    : _red;

/// Physical Health over the last [days] days (scores_daily, newest last).
Stream<PhysicalHealthView?> physicalHealthStream(int days) =>
    scoresDailyStream(days).map(PhysicalHealthView.fromDays);

/// The last [days] days of `scores_daily` documents, keyed by day.
Stream<Map<String, Map<String, dynamic>>> scoresDailyStream(int days) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return const Stream.empty();
  final today = DateTime.now();
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('scores_daily')
      .where(
        FieldPath.documentId,
        isGreaterThanOrEqualTo: localDayKey(
          DateTime(today.year, today.month, today.day - days),
        ),
      )
      .where(FieldPath.documentId, isLessThanOrEqualTo: localDayKey(today))
      .snapshots()
      .map((snapshot) => {for (final doc in snapshot.docs) doc.id: doc.data()});
}

/// Replaces the Wellness screen: Physical Health, the ingredients that make
/// it up, its trend and what would raise it (docs/scores.md §7).
class PhysicalHealthScreen extends StatefulWidget {
  const PhysicalHealthScreen({super.key});

  @override
  State<PhysicalHealthScreen> createState() => _PhysicalHealthScreenState();
}

class _PhysicalHealthScreenState extends State<PhysicalHealthScreen> {
  static const _ranges = {'4 weeks': 28, '12 weeks': 84, '6 months': 182};
  String _range = '12 weeks';
  final _stream = physicalHealthStream(182);

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return Scaffold(
      backgroundColor: colors.page,
      appBar: AppBar(title: const Text('Physical Health')),
      body: VisibleStreamBuilder<PhysicalHealthView?>(
        stream: _stream,
        builder: (context, snapshot) {
          final view = snapshot.data;
          if (view == null) {
            return Center(
              child: snapshot.connectionState == ConnectionState.waiting
                  ? const CircularProgressIndicator()
                  : Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'Your Physical Health score appears after 2 weeks of '
                        'activity and sleep data.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colors.textSecondary),
                      ),
                    ),
            );
          }
          final cutoff = DateTime.now().subtract(
            Duration(days: _ranges[_range]!),
          );
          final trend = view.trend.where((p) => p.$1.isAfter(cutoff)).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 110),
            children: [
              _Card(
                child: Row(
                  children: [
                    _Ring(score: view.score, size: 92),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label(context, 'LAST 4 WEEKS'),
                          const SizedBox(height: 6),
                          Text(
                            view.status,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            view.note,
                            style: TextStyle(color: colors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              AppSegmented<String>(
                segments: {for (final r in _ranges.keys) r: r},
                value: _range,
                onChanged: (r) => setState(() => _range = r),
              ),
              const SizedBox(height: 14),
              _Card(
                child: SizedBox(
                  height: 120,
                  child: trend.length < 2
                      ? Center(
                          child: Text(
                            'The trend starts once the score does',
                            style: TextStyle(color: colors.textSecondary),
                          ),
                        )
                      : CustomPaint(
                          painter: _TrendPainter([
                            for (final p in trend) p.$2.toDouble(),
                          ], colors.border),
                        ),
                ),
              ),
              const SizedBox(height: 22),
              _label(context, 'WHAT MAKES IT UP'),
              const SizedBox(height: 8),
              _Card(
                child: Column(
                  children: [
                    for (final (i, ingredient) in view.ingredients.indexed)
                      Padding(
                        padding: EdgeInsets.only(top: i == 0 ? 0 : 14),
                        child: _IngredientRow(ingredient: ingredient),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              _label(context, 'INSIGHTS'),
              const SizedBox(height: 8),
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final insight in view.insights)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          '• $insight',
                          style: const TextStyle(height: 1.45),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Targets follow WHO activity guidelines. VO₂ max comes from '
                'Apple Watch or Fitbit when available, otherwise it is '
                'estimated from your age, sex, height, weight and activity. '
                'A wellness estimate, not a medical assessment.',
                style: TextStyle(fontSize: 12, color: colors.textSecondary),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _label(BuildContext context, String text) => Text(
    text,
    style: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w800,
      letterSpacing: .8,
      color: context.vivordoColors.textSecondary,
    ),
  );
}

class _IngredientRow extends StatelessWidget {
  const _IngredientRow({required this.ingredient});

  final PhysicalIngredient ingredient;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final progress = ingredient.progress;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                ingredient.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              '${ingredient.weight}%',
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          ingredient.detail,
          style: TextStyle(fontSize: 13, color: colors.textSecondary),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: (progress ?? 0) / 100,
            minHeight: 6,
            color: physicalHealthColor(context, progress),
            backgroundColor: colors.cardMuted,
          ),
        ),
      ],
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.score, required this.size});

  final int? score;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: Stack(
      alignment: Alignment.center,
      children: [
        SizedBox.expand(
          child: CircularProgressIndicator(
            value: (score ?? 0) / 100,
            strokeWidth: 10,
            strokeCap: StrokeCap.round,
            color: physicalHealthColor(context, score?.toDouble()),
            backgroundColor: context.vivordoColors.cardMuted,
          ),
        ),
        Text(
          score == null ? '--' : '$score',
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
        ),
      ],
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: context.vivordoColors.card,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: context.vivordoColors.border),
    ),
    child: child,
  );
}

class _TrendPainter extends CustomPainter {
  _TrendPainter(this.values, this.grid);

  final List<double> values;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    final low = (values.reduce((a, b) => a < b ? a : b) - 5).clamp(0, 100);
    final high = (values.reduce((a, b) => a > b ? a : b) + 5).clamp(0, 100);
    final span = (high - low) == 0 ? 1 : high - low;
    Offset at(int i) => Offset(
      size.width * i / (values.length - 1),
      size.height * (1 - (values[i] - low) / span),
    );
    final line = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < values.length; i++) {
      line.lineTo(at(i).dx, at(i).dy);
    }
    final fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas
      ..drawLine(
        Offset(0, size.height),
        Offset(size.width, size.height),
        Paint()..color = grid,
      )
      ..drawPath(fill, Paint()..color = _purple.withValues(alpha: .15))
      ..drawPath(
        line,
        Paint()
          ..color = _purple
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round,
      );
  }

  @override
  bool shouldRepaint(_TrendPainter old) => old.values != values;
}
