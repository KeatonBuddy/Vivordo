import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';
import 'package:intl/intl.dart';

import '../src/services/personal_profile_service.dart';

const _purple = Color(0xFF6250E8);
const _ink = Color(0xFF17172B);
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

class PersonalProfileScreen extends StatefulWidget {
  const PersonalProfileScreen({super.key});

  @override
  State<PersonalProfileScreen> createState() => _PersonalProfileScreenState();
}

class _PersonalProfileScreenState extends State<PersonalProfileScreen> {
  _ProfileRange selectedRange = _ProfileRange.sixMonths;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.vivordoColors.page,
    appBar: AppBar(
      backgroundColor: context.vivordoColors.page,
      surfaceTintColor: Colors.transparent,
      centerTitle: true,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, ),
        onPressed: () => Navigator.pop(context),
      ),
      title: const Text(
        'Personal Profile',
        style: TextStyle(fontWeight: FontWeight.w800, ),
      ),
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

              return ListView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 34),
                children: [
                  _SummaryCard(
                    height: height,
                    weight: weight,
                    bmi: bmi,
                    bodyFat: bodyFat,
                    updatedAt: updatedAt,
                  ),
                  const SizedBox(height: 14),
                  _RangeSelector(
                    selected: selectedRange,
                    onChanged: (range) => setState(() => selectedRange = range),
                  ),
                  const SizedBox(height: 14),
                  _TrendCard(
                    title: 'Weight',
                    value: weight == null ? null : _kilogramsToPounds(weight),
                    suffix: ' lbs',
                    minimumY: 0,
                    maximumY: 300,
                    range: selectedRange,
                    points: _series(visible, (point) {
                      final kilograms = point.weight;
                      return kilograms == null
                          ? null
                          : _kilogramsToPounds(kilograms);
                    }),
                    color: _purple,
                  ),
                  const SizedBox(height: 14),
                  _TrendCard(
                    title: 'BMI',
                    value: bmi,
                    subtitle: 'Calculated from height and weight',
                    range: selectedRange,
                    points: _series(visible, (point) => point.bmi),
                    color: const Color(0xFF1478FF),
                  ),
                  const SizedBox(height: 14),
                  _TrendCard(
                    title: 'Body Fat',
                    value: bodyFat,
                    suffix: '%',
                    subtitle:
                        '${_series(points, (point) => point.bodyFat).length} measurements',
                    range: selectedRange,
                    points: _series(visible, (point) => point.bodyFat),
                    color: const Color(0xFFFF7417),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () => _openMeasurementEditor(
                      context,
                      profile: PersonalProfile(
                        heightCm: height,
                        weightKg: weight,
                        bodyFatPercent: bodyFat,
                      ),
                      title: 'Add Measurement',
                    ),
                    icon: const Icon(Icons.add_circle_outline_rounded),
                    label: const Text('Add Measurement'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _purple,
                      side: const BorderSide(color: _purple, width: 1.4),
                      minimumSize: const Size.fromHeight(54),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
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

  Future<void> _openMeasurementEditor(
    BuildContext context, {
    required PersonalProfile profile,
    required String title,
  }) async {
    final result = await showDialog<(double, double, double?)>(
      context: context,
      builder: (_) => _MeasurementEditorDialog(title: title, profile: profile),
    );
    if (result == null || !context.mounted) return;
    try {
      await PersonalProfileService.save(
        heightCm: result.$1,
        weightKg: result.$2,
        bodyFatPercent: result.$3,
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save measurement: $error')),
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

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    this.height,
    this.weight,
    this.bmi,
    this.bodyFat,
    this.updatedAt,
  });
  final double? height;
  final double? weight;
  final double? bmi;
  final double? bodyFat;
  final DateTime? updatedAt;

  String _value(double? value, String suffix) => value == null
      ? '--'
      : '${value.toStringAsFixed(value % 1 == 0 ? 0 : 1)}$suffix';

  @override
  Widget build(BuildContext context) => _Panel(
    child: Column(
      children: [
        Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _purple.withValues(alpha: .09),
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Icon(Icons.person_outline_rounded, color: _purple),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your measurements',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                Text(
                  updatedAt == null
                      ? 'No measurements yet'
                      : DateUtils.isSameDay(updatedAt, DateTime.now())
                      ? 'Updated today'
                      : 'Updated ${DateFormat('MMM d, y').format(updatedAt!)}',
                  style: const TextStyle(color: _muted),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            _SummaryMetric(label: 'HEIGHT', value: _imperialHeight(height)),
            const _VerticalDivider(),
            _SummaryMetric(
              label: 'WEIGHT',
              value: weight == null
                  ? '--'
                  : _value(_kilogramsToPounds(weight!), ' lbs'),
            ),
            const _VerticalDivider(),
            _SummaryMetric(label: 'BMI', value: _value(bmi, '')),
            const _VerticalDivider(),
            _SummaryMetric(label: 'BODY FAT', value: _value(bodyFat, '%')),
          ],
        ),
      ],
    ),
  );
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: _muted,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        FittedBox(
          child: Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    ),
  );
}

class _VerticalDivider extends StatelessWidget {
  const _VerticalDivider();
  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 42,
    color: Colors.black.withValues(alpha: .08),
  );
}

class _RangeSelector extends StatelessWidget {
  const _RangeSelector({required this.selected, required this.onChanged});
  final _ProfileRange selected;
  final ValueChanged<_ProfileRange> onChanged;
  @override
  Widget build(BuildContext context) => _Panel(
    padding: const EdgeInsets.all(8),
    child: Row(
      children: [
        for (final range in _ProfileRange.values)
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () => onChanged(range),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: selected == range ? _purple : Colors.transparent,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Text(
                  range.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: selected == range ? Colors.white : _muted,
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

class _ChartPoint {
  const _ChartPoint(this.date, this.value);
  final DateTime date;
  final double value;
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({
    required this.title,
    required this.value,
    required this.range,
    required this.points,
    required this.color,
    this.suffix = '',
    this.subtitle,
    this.minimumY,
    this.maximumY,
  });
  final String title;
  final double? value;
  final String suffix;
  final String? subtitle;
  final double? minimumY;
  final double? maximumY;
  final _ProfileRange range;
  final List<_ChartPoint> points;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final change = points.length > 1
        ? points.last.value - points.first.value
        : null;
    final favorable = change != null && change <= 0;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value == null
                          ? '--'
                          : '${value!.toStringAsFixed(1)}$suffix',
                      style: const TextStyle(
                        fontSize: 29,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle ?? _rangeLabel(range),
                      style: const TextStyle(fontSize: 13, color: _muted),
                    ),
                  ],
                ),
              ),
              if (change != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color:
                        (favorable
                                ? const Color(0xFF24B879)
                                : const Color(0xFFFF625E))
                            .withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    '${change <= 0 ? '↓' : '↑'} ${change.abs().toStringAsFixed(1)}$suffix',
                    style: TextStyle(
                      color: favorable
                          ? const Color(0xFF24B879)
                          : const Color(0xFFFF625E),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 150,
            child: points.isEmpty
                ? const Center(
                    child: Text(
                      'No measurements for this period',
                      style: TextStyle(color: _muted),
                    ),
                  )
                : _InteractiveTrendChart(
                    points: points,
                    color: color,
                    suffix: suffix,
                    minimumY: minimumY,
                    maximumY: maximumY,
                  ),
          ),
        ],
      ),
    );
  }

  static String _rangeLabel(_ProfileRange range) => switch (range) {
    _ProfileRange.month => 'Past month',
    _ProfileRange.threeMonths => 'Past 3 months',
    _ProfileRange.sixMonths => 'Past 6 months',
    _ProfileRange.year => 'Past year',
    _ProfileRange.all => 'All measurements',
  };
}

class _InteractiveTrendChart extends StatefulWidget {
  const _InteractiveTrendChart({
    required this.points,
    required this.color,
    required this.suffix,
    this.minimumY,
    this.maximumY,
  });

  final List<_ChartPoint> points;
  final Color color;
  final String suffix;
  final double? minimumY;
  final double? maximumY;

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
          minimumY: widget.minimumY,
          maximumY: widget.maximumY,
          selectedIndex: selectedIndex,
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
    this.minimumY,
    this.maximumY,
    this.selectedIndex,
  });
  final List<_ChartPoint> points;
  final Color color;
  final String suffix;
  final double? minimumY;
  final double? maximumY;
  final int? selectedIndex;

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
    final minValue = minimumY ?? midpoint - computedRange / 2;
    final maxValue = maximumY ?? midpoint + computedRange / 2;
    final displayedRange = maxValue - minValue;
    final axisDecimals = displayedRange < 10 ? 1 : 0;
    final gridPaint = Paint()
      ..color = const Color(0xFFE6E6ED)
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
        _muted,
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
    final path = Path()
      ..moveTo(location(points.first).dx, location(points.first).dy);
    for (final point in points.skip(1)) {
      final offset = location(point);
      path.lineTo(offset.dx, offset.dy);
    }
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
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
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
        _muted,
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
          style: const TextStyle(
            color: Colors.white,
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
      canvas.drawRRect(tooltipRect, Paint()..color = _ink);
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
      oldDelegate.points != points ||
      oldDelegate.color != color ||
      oldDelegate.suffix != suffix ||
      oldDelegate.minimumY != minimumY ||
      oldDelegate.maximumY != maximumY ||
      oldDelegate.selectedIndex != selectedIndex;
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.padding = const EdgeInsets.all(18)});
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: Colors.black.withValues(alpha: .06)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: .055),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: child,
  );
}

class _MeasurementEditorDialog extends StatefulWidget {
  const _MeasurementEditorDialog({required this.title, required this.profile});

  final String title;
  final PersonalProfile profile;

  @override
  State<_MeasurementEditorDialog> createState() =>
      _MeasurementEditorDialogState();
}

class _MeasurementEditorDialogState extends State<_MeasurementEditorDialog> {
  late final TextEditingController feetController;
  late final TextEditingController inchesController;
  late final TextEditingController weightController;
  late final TextEditingController bodyFatController;

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
        pounds <= 0 ||
        (bodyFat != null && (bodyFat < 0 || bodyFat > 100))) {
      return;
    }
    final height = (feet * 12 + inches) * 2.54;
    final weight = pounds / _poundsPerKilogram;
    FocusScope.of(context).unfocus();
    Navigator.pop(context, (height, weight, bodyFat));
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => FocusScope.of(context).unfocus(),
    child: AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _MeasurementLabel('Height'),
          const SizedBox(height: 7),
          Row(
            children: [
              Expanded(
                child: _MeasurementField(
                  controller: feetController,
                  hint: 'ft',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MeasurementField(
                  controller: inchesController,
                  hint: 'in',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const _MeasurementLabel('Weight'),
          const SizedBox(height: 7),
          _MeasurementField(controller: weightController, hint: 'lbs'),
          const SizedBox(height: 14),
          const _MeasurementLabel('Body Fat %'),
          const SizedBox(height: 7),
          _MeasurementField(
            controller: bodyFatController,
            hint: '% (optional)',
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    ),
  );
}

class _MeasurementLabel extends StatelessWidget {
  const _MeasurementLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
  );
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
      hintText: hint,
      hintStyle: const TextStyle(color: _muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.black.withValues(alpha: .18)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _purple, width: 1.6),
      ),
    ),
  );
}
