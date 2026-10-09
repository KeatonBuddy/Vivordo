import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';

// Widgets for Vivordo AI's reply blocks (functions/assistant.js replyBlocks):
// text, metric, action and source, plus suggestion chips.

const _brand = VivordoTheme.brand;

/// A chat bubble: the user's on the right, Vivordo AI's on the left.
class AssistantBubble extends StatelessWidget {
  const AssistantBubble({super.key, required this.text, required this.mine});

  final String text;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * (mine ? 0.8 : 0.88),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: mine ? _brand : colors.card,
            border: mine ? null : Border.all(color: colors.border),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(20),
              topRight: const Radius.circular(20),
              bottomLeft: Radius.circular(mine ? 20 : 6),
              bottomRight: Radius.circular(mine ? 6 : 20),
            ),
          ),
          child: SelectableText(
            text,
            style: TextStyle(
              color: mine ? Colors.white : colors.textPrimary,
              fontSize: 15,
              height: 1.45,
            ),
          ),
        ),
      ),
    );
  }
}

/// A small bar chart of real stored values, with the range average dashed.
class MetricChartCard extends StatelessWidget {
  const MetricChartCard({super.key, required this.block, this.onOpen});

  final Map<String, dynamic> block;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final points = [
      for (final p in (block['points'] as List? ?? const []))
        if (p is Map && p['value'] is num && p['day'] is String)
          (day: p['day'] as String, value: (p['value'] as num).toDouble()),
    ];
    if (points.length < 2) return const SizedBox.shrink();
    final average = (block['average'] as num?)?.toDouble();
    final unit = block['unit'] as String?;
    final values = [for (final p in points) p.value, ?average];
    final top = values.reduce((a, b) => a > b ? a : b);
    final bottom = values.reduce((a, b) => a < b ? a : b);
    // Bars start a little below the lowest value so differences show.
    final floor = bottom - (top - bottom) * 0.5;
    double fraction(double v) =>
        top == floor ? 1 : ((v - floor) / (top - floor)).clamp(0.05, 1);
    String day(String key) =>
        DateFormat('MMM d').format(DateTime.tryParse(key) ?? DateTime.now());
    // Whole-number series (scores, steps) get a whole-number average.
    final whole = points.every((p) => p.value == p.value.roundToDouble());
    String number(double v) => whole || v == v.roundToDouble()
        ? v.round().toString()
        : v.toStringAsFixed(1);
    const chartHeight = 96.0;

    return Semantics(
      label:
          '${block['label']} from ${day(points.first.day)} to '
          '${day(points.last.day)}, average '
          '${average == null ? 'unknown' : number(average)} ${unit ?? ''}',
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.cardMuted,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${block['label']}${unit == null ? '' : ' · $unit'}',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: chartHeight,
                child: Stack(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final p in points)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 2,
                              ),
                              child: Container(
                                height: chartHeight * fraction(p.value),
                                decoration: BoxDecoration(
                                  color: _brand.withValues(
                                    alpha: average != null && p.value < average
                                        ? 0.45
                                        : 0.85,
                                  ),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (average != null)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: chartHeight * fraction(average),
                        child: CustomPaint(
                          size: const Size(double.infinity, 1),
                          painter: _DashPainter(colors.textSecondary),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    day(points.first.day),
                    style: TextStyle(color: colors.textSecondary, fontSize: 11),
                  ),
                  const Spacer(),
                  if (average != null)
                    Text(
                      'Average ${number(average)}${unit == null ? '' : ' $unit'}',
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  const Spacer(),
                  Text(
                    day(points.last.day),
                    style: TextStyle(color: colors.textSecondary, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashPainter extends CustomPainter {
  _DashPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2;
    for (var x = 0.0; x < size.width; x += 8) {
      canvas.drawLine(Offset(x, 0), Offset(x + 4, 0), paint);
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}

/// What happened to a proposed change.
enum ActionStatus { open, running, done, cancelled, failed, expired }

/// One proposed change: what it does, and Confirm / Cancel while it's open.
class ActionCard extends StatelessWidget {
  const ActionCard({
    super.key,
    required this.action,
    required this.status,
    this.note,
    this.onConfirm,
    this.onCancel,
  });

  final Map<String, dynamic> action;
  final ActionStatus status;
  final String? note;
  final VoidCallback? onConfirm, onCancel;

  static String describe(Map<String, dynamic> action) {
    String when(String? value, {bool time = true}) {
      final parsed = DateTime.tryParse(value ?? '');
      if (parsed == null) return '';
      return DateFormat(
        time ? 'EEE, MMM d · h:mm a' : 'EEE, MMM d',
      ).format(parsed);
    }

    final operation = action['operation'];
    final title = action['title'] as String?;
    final target = action['target_title'] as String?;
    if (action['type'] == 'calendar') {
      final head = switch (operation) {
        'create' => 'Add “$title” to your calendar',
        'delete' => 'Delete “$target” from your calendar',
        _ => 'Change “$target” in your calendar',
      };
      final start = when(action['start'] as String?);
      return start.isEmpty ? head : '$head\n$start';
    }
    final head = switch (operation) {
      'create' => 'Add “$title”',
      'delete' => 'Remove “$target”',
      _ => title == null ? 'Change “$target”' : 'Rename “$target” to “$title”',
    };
    final details = [
      if (action['date'] != null) when(action['date'] as String?, time: false),
      if (action['scheduled_at'] != null)
        'at ${DateFormat('h:mm a').format(DateTime.parse(action['scheduled_at'] as String))}',
      if (action['reminder_at'] != null)
        'reminder ${DateFormat('h:mm a').format(DateTime.parse(action['reminder_at'] as String))}',
    ].where((d) => d.isNotEmpty).join(' · ');
    return details.isEmpty ? head : '$head\n$details';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final calendar = action['type'] == 'calendar';
    final (IconData icon, String label, Color color) = switch (status) {
      ActionStatus.done => (Icons.check_circle_rounded, 'Done', Colors.green),
      ActionStatus.cancelled => (
        Icons.block,
        'Cancelled',
        colors.textSecondary,
      ),
      ActionStatus.failed => (
        Icons.error_outline,
        'Not done',
        Colors.redAccent,
      ),
      ActionStatus.expired => (
        Icons.history_toggle_off,
        'Not confirmed',
        colors.textSecondary,
      ),
      _ => (
        calendar ? Icons.calendar_month_rounded : Icons.check_box_outlined,
        calendar ? 'Calendar' : 'Priority',
        _brand,
      ),
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _brand.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            describe(action),
            style: TextStyle(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          if (note != null) ...[
            const SizedBox(height: 6),
            Text(
              note!,
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
          ],
          if (status == ActionStatus.running) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(minHeight: 3),
          ],
          if (status == ActionStatus.open) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                FilledButton(
                  onPressed: onConfirm,
                  child: Text(calendar ? 'Confirm' : 'Review'),
                ),
                const SizedBox(width: 8),
                TextButton(onPressed: onCancel, child: const Text('Cancel')),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Chips naming the data a reply used; tapping one opens that screen.
class SourceChips extends StatelessWidget {
  const SourceChips({super.key, required this.sources, this.onOpen});

  final List<Map<String, dynamic>> sources;
  final void Function(String screen)? onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    String range(Map<String, dynamic> s) {
      final start = DateTime.tryParse(s['start'] as String? ?? '');
      final end = DateTime.tryParse(s['end'] as String? ?? '');
      if (start == null || end == null) return '';
      final f = DateFormat('MMM d');
      return start == end
          ? ' · ${f.format(start)}'
          : ' · ${f.format(start)}–${f.format(end)}';
    }

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final source in sources)
          ActionChip(
            avatar: const Icon(Icons.insights_rounded, size: 16, color: _brand),
            label: Text('${source['label']}${range(source)}'),
            labelStyle: const TextStyle(
              color: _brand,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            backgroundColor: colors.page,
            side: BorderSide(color: colors.border),
            shape: const StadiumBorder(),
            visualDensity: VisualDensity.compact,
            onPressed: onOpen == null || source['screen'] is! String
                ? null
                : () => onOpen!(source['screen'] as String),
          ),
      ],
    );
  }
}

/// Follow-ups to tap instead of typing.
class SuggestionChips extends StatelessWidget {
  const SuggestionChips({
    super.key,
    required this.suggestions,
    required this.onTap,
  });

  final List<String> suggestions;
  final void Function(String text)? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final s in suggestions)
          ActionChip(
            label: Text(s),
            labelStyle: const TextStyle(
              color: _brand,
              fontWeight: FontWeight.w600,
            ),
            backgroundColor: colors.card,
            side: BorderSide(color: _brand.withValues(alpha: 0.4)),
            shape: const StadiumBorder(),
            onPressed: onTap == null ? null : () => onTap!(s),
          ),
      ],
    );
  }
}
