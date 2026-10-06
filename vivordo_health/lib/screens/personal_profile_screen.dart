import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';
import 'package:intl/intl.dart';

import '../src/services/personal_profile_service.dart';
import '../src/utils/smooth_chart_path.dart';
import '../widgets/apple_ui.dart';
import '../widgets/birth_year_picker.dart';
import '../widgets/vivordo_time_picker.dart';

const _purple = Color(0xFF6250E8);
const _muted = Color(0xFF85859B);
const _poundsPerKilogram = 2.2046226218;

double _kilogramsToPounds(double kilograms) => kilograms * _poundsPerKilogram;

String _imperialHeight(double? centimeters) {
  if (centimeters == null) return '--';
  final totalInches = centimeters / 2.54;
  var feet = totalInches ~/ 12;
  var inches = (totalInches - feet * 12).round();
  if (inches == 12) {
    feet++;
    inches = 0;
  }
  return '$feet\u2032 $inches\u2033';
}

enum _ProfileRange {
  month('1M'),
  threeMonths('3M'),
  sixMonths('6M'),
  year('1Y'),
  all('All');

  const _ProfileRange(this.label);
  final String label;
}

enum _ProfileMetric {
  weight('Weight', ' lbs', _purple),
  bmi('BMI', '', Color(0xFF1478FF)),
  bodyFat('Body fat', '%', Color(0xFFFF7417));

  const _ProfileMetric(this.label, this.suffix, this.color);
  final String label;
  final String suffix;
  final Color color;
}

String _rangePhrase(_ProfileRange range) => switch (range) {
  _ProfileRange.month => 'the past month',
  _ProfileRange.threeMonths => 'the past 3 months',
  _ProfileRange.sixMonths => 'the past 6 months',
  _ProfileRange.year => 'the past year',
  _ProfileRange.all => 'all time',
};

String _measurementDay(DateTime date) {
  final local = date.toLocal();
  final now = DateTime.now();
  if (DateUtils.isSameDay(local, now)) return 'Today';
  return DateFormat(
    local.year == now.year ? 'MMM d' : 'MMM d, y',
  ).format(local);
}

class PersonalProfileScreen extends StatefulWidget {
  const PersonalProfileScreen({super.key});

  @override
  State<PersonalProfileScreen> createState() => _PersonalProfileScreenState();
}

class _PersonalProfileScreenState extends State<PersonalProfileScreen> {
  _ProfileRange selectedRange = _ProfileRange.sixMonths;
  _ProfileMetric selectedMetric = _ProfileMetric.weight;

  // ponytail: history shows the newest 12 measurements; add "Show all" if
  // anyone records more and wants to scroll back further.
  static const _historyLimit = 12;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.vivordoColors.page,
    appBar: AppBar(
      backgroundColor: context.vivordoColors.page,
      surfaceTintColor: Colors.transparent,
      centerTitle: true,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded),
        onPressed: () => Navigator.pop(context),
      ),
      title: const Text(
        'Personal Profile',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      actions: [
        IconButton(
          tooltip: 'Your profile',
          icon: const Icon(Icons.account_circle_outlined),
          onPressed: () => _openProfile(context),
        ),
      ],
    ),
    body: StreamBuilder<PersonalProfile>(
      stream: PersonalProfileService.watch(),
      initialData: const PersonalProfile(),
      builder: (context, profileSnapshot) =>
          StreamBuilder<List<PersonalProfileMeasurement>>(
            stream: PersonalProfileService.watchMeasurements(),
            initialData: const [],
            builder: (context, measurementSnapshot) {
              final profile = profileSnapshot.data ?? const PersonalProfile();
              final points = _buildPoints(
                profile,
                measurementSnapshot.data ?? const [],
              );
              final visible = _filter(points);
              final latest = points.isEmpty ? null : points.last;
              final height = profile.heightCm ?? latest?.height;
              final weight = profile.weightKg ?? latest?.weight;
              final bodyFat = profile.bodyFatPercent ?? latest?.bodyFat;
              final bmi = _bmi(height, weight);
              final updatedAt = profile.updatedAt ?? latest?.date;

              final weightSeries = _series(visible, (point) {
                final kilograms = point.weight;
                return kilograms == null ? null : _kilogramsToPounds(kilograms);
              });
              final metricSeries = switch (selectedMetric) {
                _ProfileMetric.weight => weightSeries,
                _ProfileMetric.bmi => _series(visible, (point) => point.bmi),
                _ProfileMetric.bodyFat => _series(
                  visible,
                  (point) => point.bodyFat,
                ),
              };
              final history = points.reversed
                  .take(_historyLimit)
                  .toList(growable: false);

              return ListView(
                physics: const BouncingScrollPhysics(),
                // Leaves room to scroll the last row clear of the assistant
                // bubble in the bottom-right corner.
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 110),
                children: [
                  _ProfileHero(
                    height: height,
                    weight: weight,
                    bmi: bmi,
                    bodyFat: bodyFat,
                    updatedAt: updatedAt,
                    weightSeries: weightSeries,
                    range: selectedRange,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: () => _openMeasurementEditor(
                        context,
                        profile: PersonalProfile(
                          heightCm: height,
                          weightKg: weight,
                          bodyFatPercent: bodyFat,
                        ),
                        title: 'Add Measurement',
                      ),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text(
                        'Add measurement',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: _purple,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const _SectionLabel('TRENDS'),
                  const SizedBox(height: 10),
                  _TrendCard(
                    metric: selectedMetric,
                    range: selectedRange,
                    points: metricSeries,
                    onMetricChanged: (metric) =>
                        setState(() => selectedMetric = metric),
                    onRangeChanged: (range) =>
                        setState(() => selectedRange = range),
                  ),
                  if (history.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    const _SectionLabel('HISTORY'),
                    const SizedBox(height: 10),
                    _Panel(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: Column(
                        children: [
                          for (var i = 0; i < history.length; i++)
                            _HistoryRow(
                              point: history[i],
                              divider: i < history.length - 1,
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
    ),
  );

  List<_ProfilePoint> _buildPoints(
    PersonalProfile profile,
    List<PersonalProfileMeasurement> measurements,
  ) {
    final points = <_ProfilePoint>[];
    for (final measurement in measurements) {
      points.add(
        _ProfilePoint(
          date: measurement.recordedAt,
          height: measurement.heightCm,
          weight: measurement.weightKg,
          bodyFat: measurement.bodyFatPercent,
        ),
      );
    }
    // Older profiles may only have the latest summary and no history document.
    // Once history exists, that summary mirrors the newest measurement and
    // should not be plotted as a duplicate point.
    if (measurements.isEmpty && profile.updatedAt != null) {
      points.add(
        _ProfilePoint(
          date: profile.updatedAt!,
          height: profile.heightCm,
          weight: profile.weightKg,
          bodyFat: profile.bodyFatPercent,
        ),
      );
    }
    points.sort((a, b) => a.date.compareTo(b.date));
    double? lastHeight;
    return [
      for (final point in points)
        _ProfilePoint(
          date: point.date,
          height: lastHeight = point.height ?? lastHeight,
          weight: point.weight,
          bodyFat: point.bodyFat,
        ),
    ];
  }

  List<_ProfilePoint> _filter(List<_ProfilePoint> points) {
    if (selectedRange == _ProfileRange.all) return points;
    final now = DateTime.now();
    final months = switch (selectedRange) {
      _ProfileRange.month => 1,
      _ProfileRange.threeMonths => 3,
      _ProfileRange.sixMonths => 6,
      _ProfileRange.year => 12,
      _ProfileRange.all => 1200,
    };
    final start = _subtractCalendarMonths(now, months);
    return points
        .where(
          (point) => !point.date.isBefore(start) && !point.date.isAfter(now),
        )
        .toList(growable: false);
  }

  DateTime _subtractCalendarMonths(DateTime date, int months) {
    final targetMonthIndex = date.year * 12 + date.month - 1 - months;
    final targetYear = targetMonthIndex ~/ 12;
    final targetMonth = targetMonthIndex % 12 + 1;
    final lastDay = DateTime(targetYear, targetMonth + 1, 0).day;
    return DateTime(
      targetYear,
      targetMonth,
      math.min(date.day, lastDay),
      date.hour,
      date.minute,
      date.second,
      date.millisecond,
      date.microsecond,
    );
  }

  List<_ChartPoint> _series(
    List<_ProfilePoint> points,
    double? Function(_ProfilePoint point) value,
  ) => [
    for (final point in points)
      if (value(point) case final metric?) _ChartPoint(point.date, metric),
  ];

  /// Height, weight, age and sex: what Physical Health compares against.
  Future<void> _openProfile(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: context.vivordoColors.page,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => SafeArea(
      child: Padding(
        // Bottom room keeps the note clear of the assistant bubble.
        padding: const EdgeInsets.fromLTRB(18, 22, 18, 84),
        child: StreamBuilder<PersonalProfile>(
          stream: PersonalProfileService.watch(),
          builder: (sheetContext, snapshot) {
            final profile = snapshot.data ?? const PersonalProfile();
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your profile',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 14),
                _AboutYou(
                  profile: profile,
                  onEditBody: () => _openMeasurementEditor(
                    sheetContext,
                    profile: profile,
                    title: 'Update Measurement',
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );

  Future<void> _openMeasurementEditor(
    BuildContext context, {
    required PersonalProfile profile,
    required String title,
  }) async {
    final result =
        await showModalBottomSheet<(double, double, double?, DateTime)>(
          context: context,
          useRootNavigator: true,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) =>
              MeasurementEditorSheet(title: title, profile: profile),
        );
    if (result == null || !context.mounted) return;
    try {
      await PersonalProfileService.save(
        heightCm: result.$1,
        weightKg: result.$2,
        bodyFatPercent: result.$3,
        recordedAt: result.$4,
      );
    } catch (error) {
      debugPrint('Could not save measurement: $error');
      if (!context.mounted) return;
      showToast(
        context,
        "Couldn't save the measurement. Try again.",
        kind: ToastKind.error,
      );
    }
  }
}

class _ProfilePoint {
  const _ProfilePoint({
    required this.date,
    this.height,
    this.weight,
    this.bodyFat,
  });
  final DateTime date;
  final double? height;
  final double? weight;
  final double? bodyFat;
  double? get bmi => _bmi(height, weight);
}

double? _bmi(double? height, double? weight) =>
    height != null && height > 0 && weight != null
    ? weight / math.pow(height / 100, 2)
    : null;

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({
    required this.height,
    required this.weight,
    required this.bmi,
    required this.bodyFat,
    required this.updatedAt,
    required this.weightSeries,
    required this.range,
  });

  final double? height, weight, bmi, bodyFat;
  final DateTime? updatedAt;
  final List<_ChartPoint> weightSeries;
  final _ProfileRange range;

  static String _value(double? value, String suffix) => value == null
      ? '--'
      : '${value.toStringAsFixed(value % 1 == 0 ? 0 : 1)}$suffix';

  @override
  Widget build(BuildContext context) {
    final change = weightSeries.length > 1
        ? weightSeries.last.value - weightSeries.first.value
        : null;
    final changeText = weight == null
        ? 'Add your first measurement to start tracking.'
        : change == null
        ? 'Add another measurement to see your trend.'
        : change.abs() < .05
        ? 'No change over ${_rangePhrase(range)}'
        : '${change < 0 ? '↓' : '↑'} ${change.abs().toStringAsFixed(1)} lbs over ${_rangePhrase(range)}';
    const subtle = Color(0xFFE8E0FF);
    final divider = Container(
      width: 1,
      height: 34,
      color: Colors.white.withValues(alpha: .15),
    );
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFFAA91FF).withValues(alpha: .6),
        ),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF5844ED), Color(0xFF3529AD)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'CURRENT WEIGHT',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.3,
                    color: subtle,
                  ),
                ),
              ),
              if (updatedAt != null)
                Text(
                  DateUtils.isSameDay(updatedAt, DateTime.now())
                      ? 'Updated today'
                      : 'Updated ${DateFormat('MMM d, y').format(updatedAt!)}',
                  style: const TextStyle(fontSize: 12, color: subtle),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: weight == null
                      ? '--'
                      : _kilogramsToPounds(weight!).toStringAsFixed(1),
                ),
                if (weight != null)
                  const TextSpan(text: ' lbs', style: TextStyle(fontSize: 16)),
              ],
            ),
            style: const TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          Text(
            changeText,
            style: const TextStyle(fontSize: 13, color: Color(0xFFF1ECFF)),
          ),
          const SizedBox(height: 14),
          Container(height: 1, color: Colors.white.withValues(alpha: .15)),
          const SizedBox(height: 12),
          Row(
            children: [
              _HeroMetric(label: 'height', value: _imperialHeight(height)),
              divider,
              _HeroMetric(label: 'BMI', value: _value(bmi, '')),
              divider,
              _HeroMetric(label: 'body fat', value: _value(bodyFat, '%')),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Color(0xFFE8E0FF)),
        ),
      ],
    ),
  );
}

/// Height, weight, age and sex: the inputs to Physical Health's fitness
/// norms and VO₂ max estimate. Age and sex are also asked in onboarding.
class _AboutYou extends StatelessWidget {
  const _AboutYou({required this.profile, required this.onEditBody});

  final PersonalProfile profile;
  final VoidCallback onEditBody;

  Future<void> _save(
    BuildContext context, {
    int? birthYear,
    String? sex,
  }) async {
    try {
      await PersonalProfileService.saveAbout(birthYear: birthYear, sex: sex);
    } catch (_) {
      if (context.mounted) {
        showToast(context, "Couldn't save. Try again.", kind: ToastKind.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final weight = profile.weightKg;
    Widget row(String label, String? value, VoidCallback onTap) => InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              value ?? 'Add',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: value == null ? _purple : null,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, color: colors.textSecondary),
          ],
        ),
      ),
    );
    final divider = Divider(height: 24, color: colors.border);
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          row(
            'Height',
            profile.heightCm == null ? null : _imperialHeight(profile.heightCm),
            onEditBody,
          ),
          divider,
          row(
            'Weight',
            weight == null
                ? null
                : '${_kilogramsToPounds(weight).toStringAsFixed(1)} lbs',
            onEditBody,
          ),
          divider,
          row('Age', profile.age?.toString(), () async {
            final year = await showBirthYearPicker(
              context,
              initial: profile.birthYear,
            );
            if (year != null && context.mounted) {
              await _save(context, birthYear: year);
            }
          }),
          divider,
          const Text('Sex', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          _Choice<String?>(
            values: profileSexes,
            selected: profile.sex,
            label: (value) => profileSexLabels[value] ?? '',
            onChanged: (value) => _save(context, sex: value),
          ),
          const SizedBox(height: 10),
          Text(
            'Physical Health uses these to compare your fitness with '
            'people like you.',
            style: TextStyle(fontSize: 12, color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.3,
      color: context.vivordoColors.textSecondary,
    ),
  );
}

class _Choice<T> extends StatelessWidget {
  const _Choice({
    required this.values,
    required this.selected,
    required this.label,
    required this.onChanged,
  });
  final List<T> values;
  final T selected;
  final String Function(T value) label;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: context.vivordoColors.input,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        for (final value in values)
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => onChanged(value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: selected == value ? _purple : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  label(value),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: selected == value ? Colors.white : _muted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.point, required this.divider});
  final _ProfilePoint point;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final weight = point.weight;
    final bodyFat = point.bodyFat;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(
        border: divider
            ? Border(bottom: BorderSide(color: context.vivordoColors.border))
            : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _measurementDay(point.date),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            weight == null
                ? '--'
                : '${_kilogramsToPounds(weight).toStringAsFixed(1)} lbs',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          SizedBox(
            width: 64,
            child: Text(
              bodyFat == null ? '--' : '${bodyFat.toStringAsFixed(1)}%',
              textAlign: TextAlign.right,
              style: const TextStyle(color: _muted),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartPoint {
  const _ChartPoint(this.date, this.value);
  final DateTime date;
  final double value;
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({
    required this.metric,
    required this.range,
    required this.points,
    required this.onMetricChanged,
    required this.onRangeChanged,
  });
  final _ProfileMetric metric;
  final _ProfileRange range;
  final List<_ChartPoint> points;
  final ValueChanged<_ProfileMetric> onMetricChanged;
  final ValueChanged<_ProfileRange> onRangeChanged;

  @override
  Widget build(BuildContext context) {
    final delta = points.length > 1
        ? points.last.value - points.first.value
        : null;
    final change = delta == null || delta.abs() < .05 ? null : delta;
    final favorable = change != null && change <= 0;
    final changeColor = favorable
        ? const Color(0xFF24B879)
        : const Color(0xFFFF625E);
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Choice<_ProfileMetric>(
            values: _ProfileMetric.values,
            selected: metric,
            label: (metric) => metric.label,
            onChanged: onMetricChanged,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  metric == _ProfileMetric.bmi
                      ? 'Calculated from height and weight'
                      : '${points.length} ${points.length == 1 ? 'measurement' : 'measurements'} in ${_rangePhrase(range)}',
                  style: const TextStyle(fontSize: 13, color: _muted),
                ),
              ),
              if (change != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: changeColor.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${change <= 0 ? '↓' : '↑'} ${change.abs().toStringAsFixed(1)}${metric.suffix}',
                    style: TextStyle(
                      color: changeColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 170,
            child: points.isEmpty
                ? const Center(
                    child: Text(
                      'No measurements for this period',
                      style: TextStyle(color: _muted),
                    ),
                  )
                : _InteractiveTrendChart(
                    points: points,
                    color: metric.color,
                    suffix: metric.suffix,
                  ),
          ),
          const SizedBox(height: 12),
          _Choice<_ProfileRange>(
            values: _ProfileRange.values,
            selected: range,
            label: (range) => range.label,
            onChanged: onRangeChanged,
          ),
        ],
      ),
    );
  }
}

class _InteractiveTrendChart extends StatefulWidget {
  const _InteractiveTrendChart({
    required this.points,
    required this.color,
    required this.suffix,
  });

  final List<_ChartPoint> points;
  final Color color;
  final String suffix;

  @override
  State<_InteractiveTrendChart> createState() => _InteractiveTrendChartState();
}

class _InteractiveTrendChartState extends State<_InteractiveTrendChart> {
  int? selectedIndex;

  double _elapsed(DateTime date, DateTime start) =>
      date.difference(start).inMilliseconds.toDouble();

  void _select(Offset position, double width) {
    const chartLeft = 6.0;
    const chartRight = 42.0;
    final chartWidth = math.max(width - chartLeft - chartRight, 1);
    final firstDate = widget.points.first.date;
    final lastDate = widget.points.last.date;
    final dateSpan = math.max(_elapsed(lastDate, firstDate), 1);
    var nearestIndex = 0;
    var nearestDistance = double.infinity;
    for (var index = 0; index < widget.points.length; index++) {
      final point = widget.points[index];
      final pointX =
          chartLeft + chartWidth * _elapsed(point.date, firstDate) / dateSpan;
      final distance = (position.dx - pointX).abs();
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestIndex = index;
      }
    }
    if (selectedIndex != nearestIndex) {
      setState(() => selectedIndex = nearestIndex);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) =>
          _select(details.localPosition, constraints.maxWidth),
      onHorizontalDragStart: (details) =>
          _select(details.localPosition, constraints.maxWidth),
      onHorizontalDragUpdate: (details) =>
          _select(details.localPosition, constraints.maxWidth),
      child: CustomPaint(
        painter: _TrendPainter(
          points: widget.points,
          color: widget.color,
          suffix: widget.suffix,
          selectedIndex: selectedIndex,
          dark: Theme.of(context).brightness == Brightness.dark,
        ),
        child: const SizedBox.expand(),
      ),
    ),
  );
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter({
    required this.points,
    required this.color,
    required this.suffix,
    this.selectedIndex,
    required this.dark,
  });
  final List<_ChartPoint> points;
  final Color color;
  final String suffix;
  final int? selectedIndex;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 6.0;
    const right = 42.0;
    const top = 8.0;
    const bottom = 24.0;
    final width = size.width - left - right;
    final height = size.height - top - bottom;
    final values = points.map((point) => point.value);
    final dataMin = values.reduce(math.min);
    final dataMax = values.reduce(math.max);
    final dataRange = dataMax - dataMin;
    final minimumRange = suffix == ' lbs'
        ? 4.0
        : suffix == '%'
        ? 2.0
        : .8;
    final computedRange = math.max(dataRange * 1.3, minimumRange);
    final midpoint = (dataMin + dataMax) / 2;
    final minValue = midpoint - computedRange / 2;
    final maxValue = midpoint + computedRange / 2;
    final displayedRange = maxValue - minValue;
    final axisDecimals = displayedRange < 10 ? 1 : 0;
    final gridPaint = Paint()
      ..color = (dark ? Colors.white : Colors.black).withValues(alpha: .08)
      ..strokeWidth = 1;
    for (var index = 0; index < 4; index++) {
      final y = top + height * index / 3;
      canvas.drawLine(Offset(left, y), Offset(left + width, y), gridPaint);
      _drawText(
        canvas,
        (maxValue - (maxValue - minValue) * index / 3).toStringAsFixed(
          axisDecimals,
        ),
        Offset(left + width + 8, y - 7),
        11,
        dark ? Colors.white54 : Colors.black45,
      );
    }
    final firstDate = points.first.date;
    final lastDate = points.last.date;
    final dateSpan = math.max(
      lastDate.difference(firstDate).inMilliseconds.toDouble(),
      1,
    );
    Offset location(_ChartPoint point) => Offset(
      left + width * point.date.difference(firstDate).inMilliseconds / dateSpan,
      top + height * (maxValue - point.value) / (maxValue - minValue),
    );
    final locations = points.map(location).toList(growable: false);
    final path = smoothChartPath(locations);
    final fill = Path.from(path)
      ..lineTo(location(points.last).dx, top + height)
      ..lineTo(location(points.first).dx, top + height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: .18), color.withValues(alpha: 0)],
        ).createShader(Rect.fromLTWH(left, top, width, height)),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    for (final point in points) {
      final offset = location(point);
      canvas.drawCircle(offset, 4.5, Paint()..color = color);
      canvas.drawCircle(offset, 2.5, Paint()..color = Colors.white);
    }
    final labels = points.length <= 4
        ? points
        : [points.first, points[points.length ~/ 2], points.last];
    for (final point in labels) {
      final offset = location(point);
      _drawText(
        canvas,
        DateFormat('MMM').format(point.date),
        Offset(offset.dx - 11, top + height + 7),
        11,
        dark ? Colors.white54 : Colors.black45,
      );
    }
    final selected = selectedIndex;
    if (selected != null && selected >= 0 && selected < points.length) {
      final point = points[selected];
      final offset = location(point);
      canvas.drawLine(
        Offset(offset.dx, top),
        Offset(offset.dx, top + height),
        Paint()
          ..color = color.withValues(alpha: .35)
          ..strokeWidth = 1.2,
      );
      canvas.drawCircle(offset, 8, Paint()..color = Colors.white);
      canvas.drawCircle(offset, 6, Paint()..color = color);

      final tooltip = TextPainter(
        text: TextSpan(
          text:
              '${point.value.toStringAsFixed(1)}$suffix  ·  ${DateFormat('MMM d, y').format(point.date)}',
          style: TextStyle(
            color: dark ? Colors.white : Colors.black,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      const horizontalPadding = 9.0;
      const verticalPadding = 6.0;
      final tooltipSize = Size(
        tooltip.width + horizontalPadding * 2,
        tooltip.height + verticalPadding * 2,
      );
      var tooltipLeft = offset.dx - tooltipSize.width / 2;
      tooltipLeft = tooltipLeft.clamp(0, size.width - tooltipSize.width);
      var tooltipTop = offset.dy - tooltipSize.height - 10;
      if (tooltipTop < 0) tooltipTop = offset.dy + 10;
      final tooltipRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          tooltipLeft,
          tooltipTop,
          tooltipSize.width,
          tooltipSize.height,
        ),
        const Radius.circular(8),
      );
      canvas.drawRRect(
        tooltipRect,
        Paint()..color = dark ? const Color(0xFF302B48) : Colors.white,
      );
      tooltip.paint(
        canvas,
        Offset(tooltipLeft + horizontalPadding, tooltipTop + verticalPadding),
      );
    }
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset offset,
    double size,
    Color color,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: size, color: color),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      !listEquals(oldDelegate.points, points) ||
      oldDelegate.color != color ||
      oldDelegate.suffix != suffix ||
      oldDelegate.selectedIndex != selectedIndex ||
      oldDelegate.dark != dark;
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.padding = const EdgeInsets.all(18)});
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: context.vivordoColors.card,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: context.vivordoColors.border),
      boxShadow: [
        BoxShadow(
          color: context.vivordoColors.shadow,
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: child,
  );
}

class MeasurementEditorSheet extends StatefulWidget {
  const MeasurementEditorSheet({
    super.key,
    required this.title,
    required this.profile,
  });

  final String title;
  final PersonalProfile profile;

  @override
  State<MeasurementEditorSheet> createState() =>
      _MeasurementEditorDialogState();
}

class _MeasurementEditorDialogState extends State<MeasurementEditorSheet> {
  late final TextEditingController feetController;
  late final TextEditingController inchesController;
  late final TextEditingController weightController;
  late final TextEditingController bodyFatController;
  DateTime selectedDate = DateUtils.dateOnly(DateTime.now());
  String? error;

  String _text(double? value) =>
      value?.toStringAsFixed(value % 1 == 0 ? 0 : 1) ?? '';

  @override
  void initState() {
    super.initState();
    final totalInches = (widget.profile.heightCm ?? 0) / 2.54;
    final feet = totalInches ~/ 12;
    final inches = totalInches - feet * 12;
    feetController = TextEditingController(
      text: widget.profile.heightCm == null ? '' : '$feet',
    );
    inchesController = TextEditingController(
      text: widget.profile.heightCm == null ? '' : _text(inches),
    );
    weightController = TextEditingController(
      text: widget.profile.weightKg == null
          ? ''
          : _text(_kilogramsToPounds(widget.profile.weightKg!)),
    );
    bodyFatController = TextEditingController(
      text: _text(widget.profile.bodyFatPercent),
    );
  }

  @override
  void dispose() {
    feetController.dispose();
    inchesController.dispose();
    weightController.dispose();
    bodyFatController.dispose();
    super.dispose();
  }

  void _save() {
    final feet = int.tryParse(feetController.text);
    final inches = double.tryParse(inchesController.text);
    final pounds = double.tryParse(weightController.text);
    final bodyFat = bodyFatController.text.trim().isEmpty
        ? null
        : double.tryParse(bodyFatController.text);
    if (feet == null ||
        feet <= 0 ||
        inches == null ||
        inches < 0 ||
        inches >= 12 ||
        pounds == null ||
        !pounds.isFinite ||
        pounds <= 0 ||
        !inches.isFinite ||
        (bodyFatController.text.trim().isNotEmpty && bodyFat == null) ||
        (bodyFat != null &&
            (!bodyFat.isFinite || bodyFat < 0 || bodyFat > 100))) {
      setState(
        () => error =
            'Enter a valid height and weight. Body fat is optional (0–100%).',
      );
      return;
    }
    final height = (feet * 12 + inches) * 2.54;
    final weight = pounds / _poundsPerKilogram;
    FocusScope.of(context).unfocus();
    final now = DateTime.now();
    final recordedAt = DateUtils.isSameDay(selectedDate, now)
        ? now
        : DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
    Navigator.pop(context, (height, weight, bodyFat, recordedAt));
  }

  Future<void> _pickDate() async {
    FocusScope.of(context).unfocus();
    final date = await showVivordoDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(1900),
      lastDate: DateUtils.dateOnly(DateTime.now()),
    );
    if (date != null && mounted) setState(() => selectedDate = date);
  }

  Widget _group(Widget child) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
    decoration: BoxDecoration(
      color: context.vivordoColors.card,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: context.vivordoColors.textSecondary.withValues(alpha: .18),
      ),
    ),
    child: child,
  );

  Widget _row(
    IconData icon,
    String title,
    Widget input, {
    bool optional = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final label = Row(
          children: [
            Icon(icon, color: const Color(0xFFAA9AFF), size: 27),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (optional)
                    Text(
                      'Optional',
                      style: TextStyle(
                        fontSize: 11,
                        color: context.vivordoColors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
        if (constraints.maxWidth < 300 ||
            MediaQuery.textScalerOf(context).scale(16) > 21) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [label, const SizedBox(height: 10), input],
          );
        }
        return Row(
          children: [
            Expanded(child: label),
            const SizedBox(width: 10),
            Expanded(flex: 1, child: input),
          ],
        );
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color: colors.page,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(
            color: colors.textSecondary.withValues(alpha: .25),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 30,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.textSecondary,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const SizedBox(width: 44),
                    Expanded(
                      child: Text(
                        widget.title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  'MEASUREMENTS',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Update your height and weight. Body fat is optional.',
                  style: TextStyle(color: colors.textSecondary),
                ),
                const SizedBox(height: 12),
                _group(
                  Column(
                    children: [
                      _row(
                        Icons.straighten_rounded,
                        'Height',
                        Row(
                          children: [
                            Expanded(
                              child: _MeasurementField(
                                controller: feetController,
                                hint: 'ft',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _MeasurementField(
                                controller: inchesController,
                                hint: 'in',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      _row(
                        Icons.monitor_weight_outlined,
                        'Weight',
                        _MeasurementField(
                          controller: weightController,
                          hint: 'lb',
                        ),
                      ),
                      const Divider(height: 1),
                      _row(
                        Icons.percent_rounded,
                        'Body fat',
                        _MeasurementField(
                          controller: bodyFatController,
                          hint: '%',
                        ),
                        optional: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  'DATE',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 10),
                _group(
                  InkWell(
                    onTap: _pickDate,
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.calendar_month_rounded,
                            color: Color(0xFFAA9AFF),
                            size: 27,
                          ),
                          const SizedBox(width: 12),
                          const Text('Date'),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                if (DateUtils.isSameDay(
                                  selectedDate,
                                  DateTime.now(),
                                ))
                                  const Text('Today'),
                                Text(
                                  DateFormat.yMMMMd().format(selectedDate),
                                  textAlign: TextAlign.right,
                                  style: TextStyle(color: colors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                    ),
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF4935F4), Color(0xFF7865F5)],
                    ),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: TextButton(
                    onPressed: _save,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                    ),
                    child: const Text(
                      'Save Measurement',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MeasurementField extends StatelessWidget {
  const _MeasurementField({required this.controller, required this.hint});
  final TextEditingController controller;
  final String hint;
  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(
      suffixText: hint,
      filled: true,
      fillColor: context.vivordoColors.textSecondary.withValues(alpha: .08),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: context.vivordoColors.textSecondary.withValues(alpha: .18),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _purple, width: 1.6),
      ),
    ),
  );
}
