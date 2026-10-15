import 'package:flutter/material.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';

import '../src/utils/score_breakdown.dart';
import 'apple_ui.dart';
import 'event_type_section.dart';

/// A group of breakdown rows under an optional heading ("MENTAL · 14").
typedef BreakdownSection = ({String? heading, List<BreakdownRow> rows});

/// Why a score is what it is: the score, a line on how it compares, then
/// each part with the points it adds or (for Capacity, [signed]) how much
/// it moved the score against your usual. A row for an event opens its
/// Event type, so a wrong number can be fixed from here.
Future<void> showScoreBreakdown(
  BuildContext context, {
  required String kicker,
  required int score,
  required String summary,
  required List<BreakdownSection> sections,
  required String footer,
  bool signed = false,
  String empty = 'Nothing to count yet.',
}) => showAppleSheet<void>(
  context,
  builder: (sheetContext) {
    final colors = sheetContext.vivordoColors;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * .85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                kicker,
                style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w700,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$score',
                style: TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w800,
                  color: colors.textPrimary,
                ),
              ),
              Text(
                summary,
                style: TextStyle(fontSize: 14, color: colors.textSecondary),
              ),
              if (sections.every((section) => section.rows.isEmpty)) ...[
                const SizedBox(height: 14),
                Text(
                  empty,
                  style: TextStyle(fontSize: 14, color: colors.textSecondary),
                ),
              ],
              for (final section in sections)
                if (section.rows.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  if (section.heading case final heading?)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        heading,
                        style: TextStyle(
                          fontSize: 12,
                          letterSpacing: 1,
                          fontWeight: FontWeight.w700,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  for (final row in section.rows)
                    _BreakdownRowView(row: row, signed: signed),
                ],
              const SizedBox(height: 12),
              Text(
                footer,
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

class _BreakdownRowView extends StatelessWidget {
  const _BreakdownRowView({required this.row, required this.signed});

  final BreakdownRow row;
  final bool signed;

  String get _points {
    final points = row.points;
    if (points == null) return '—';
    if (!signed) return points.toStringAsFixed(1);
    final rounded = points.round();
    return rounded > 0
        ? '+$rounded'
        : rounded < 0
        ? '−${-rounded}'
        : '0';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final points = row.points;
    final pointsColor = !signed || points == null || points.round() == 0
        ? colors.textSecondary
        : points > 0
        ? const Color(0xFF1D9E75)
        : const Color(0xFFD14343);
    // An event (not a priority) opens its Event type.
    final event = row.item?.score.category == 'priority'
        ? null
        : row.item?.event;
    final content = Opacity(
      opacity: row.leftOut ? .6 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    row.detail,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.3,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (row.chip case final chip?) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: VivordoTheme.brand.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  chip,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: VivordoTheme.brand,
                  ),
                ),
              ),
            ],
            const SizedBox(width: 10),
            SizedBox(
              width: 42,
              child: Text(
                _points,
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: pointsColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.border, width: .5)),
      ),
      child: event == null
          ? content
          : InkWell(
              onTap: () => showAppleSheet<void>(
                context,
                builder: (_) => SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.title.isEmpty ? 'Untitled' : event.title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 14),
                        EventTypeSection(event: event),
                      ],
                    ),
                  ),
                ),
              ),
              child: content,
            ),
    );
  }
}
