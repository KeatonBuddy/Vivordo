import 'package:flutter/material.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';

import '../src/utils/score_breakdown.dart';
import 'apple_ui.dart';
import 'daily_brief_card.dart';
import 'event_type_section.dart';

/// A group of breakdown rows under an optional heading ("SCHEDULE · 14").
typedef BreakdownSection = ({String? heading, List<BreakdownRow> rows});

/// Why a score is what it is: the score, a line on how it compares, then
/// each part with the points it adds or (for Capacity, [signed]) how much
/// it moved the score against your usual. A row for an event opens its
/// Event type, so a wrong number can be fixed from here. In words view
/// ([words] is the score's state) the score is that word and each row a
/// state chip from [breakdownWords], biggest first.
Future<void> showScoreBreakdown(
  BuildContext context, {
  required String kicker,
  required int score,
  required String summary,
  required List<BreakdownSection> sections,
  required String footer,
  bool signed = false,
  String empty = 'Nothing to count yet.',
  BriefState? words,
  Widget? history,
}) => showAppleSheet<void>(
  context,
  builder: (sheetContext) {
    final colors = sheetContext.vivordoColors;
    final allRows = [for (final section in sections) ...section.rows];
    final whole = signed
        ? const <BreakdownRow, int>{}
        : wholePoints(allRows, score);
    final states = words == null
        ? null
        : breakdownWords(allRows, signed: signed);
    // Words view lists the biggest first; numbers keep the day's order.
    List<BreakdownRow> ordered(List<BreakdownRow> rows) => states == null
        ? rows
        : ([...rows]
            ..sort((a, b) => _size(b, signed).compareTo(_size(a, signed))));
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
                words?.word ?? '$score',
                style: TextStyle(
                  fontSize: words == null ? 38 : 28,
                  fontWeight: FontWeight.w800,
                  color: colors.textPrimary,
                ),
              ),
              Text(
                summary,
                style: TextStyle(fontSize: 14, color: colors.textSecondary),
              ),
              ?history,
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
                  for (final row in ordered(section.rows))
                    _BreakdownRowView(
                      row: row,
                      signed: signed,
                      whole: whole[row],
                      state: states?[row],
                    ),
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

/// Each counted row's points as a whole number, rounded so they add up to
/// [score]: the rows with the biggest fractions round up (largest
/// remainder). Plain rounding when [score] isn't within reach of the rows.
Map<BreakdownRow, int> wholePoints(List<BreakdownRow> rows, int score) {
  final counted = [
    for (final row in rows)
      if (!row.leftOut && row.points != null) row,
  ];
  final floors = {for (final row in counted) row: row.points!.floor()};
  final short = score - floors.values.fold(0, (a, b) => a + b);
  if (short < 0 || short > counted.length) {
    return {for (final row in counted) row: row.points!.round()};
  }
  final byFraction = [...counted]
    ..sort(
      (a, b) => (b.points! - b.points!.floor()).compareTo(
        a.points! - a.points!.floor(),
      ),
    );
  return {
    for (final row in counted)
      row: floors[row]! + (byFraction.indexOf(row) < short ? 1 : 0),
  };
}

double _size(BreakdownRow row, bool signed) => row.leftOut || row.points == null
    ? -1
    : signed
    ? row.points!.abs()
    : row.points!;

/// Words view: each counted row's points as a state. [signed] (Capacity):
/// Helped or Held it back, with "most" on the row that moved it most, and
/// No change under half a point. Otherwise (Demand, Effort) the row's
/// share of the day's total, so a row never argues with the headline: a
/// light day's only row is "All of it", not "Heavy".
Map<BreakdownRow, BriefState> breakdownWords(
  List<BreakdownRow> rows, {
  required bool signed,
}) {
  final counted = [
    for (final row in rows)
      if (!row.leftOut && row.points != null) row,
  ];
  if (counted.isEmpty) return {};
  final biggest = counted.reduce(
    (a, b) => _size(b, signed) > _size(a, signed) ? b : a,
  );
  final total = counted.fold<double>(0, (sum, row) => sum + row.points!);
  BriefState wordFor(BreakdownRow row) {
    final points = row.points!;
    if (signed) {
      // "Most" only means something with more than one to compare.
      final most = row == biggest && counted.length > 1;
      if (points.round() == 0) {
        return (word: 'No change', tone: BriefTone.usual);
      }
      return points > 0
          ? (word: most ? 'Helped most' : 'Helped', tone: BriefTone.good)
          : (
              word: most ? 'Held it back most' : 'Held it back',
              tone: BriefTone.low,
            );
    }
    if (counted.length == 1) return (word: 'All of it', tone: BriefTone.usual);
    final share = total <= 0 ? 0 : points / total;
    return switch (share) {
      >= .6 => (word: 'Most of it', tone: BriefTone.low),
      >= .4 => (word: 'About half', tone: BriefTone.low),
      >= .2 => (word: 'A good part', tone: BriefTone.usual),
      >= .1 => (word: 'Some', tone: BriefTone.good),
      _ => (word: 'A little', tone: BriefTone.good),
    };
  }

  return {for (final row in counted) row: wordFor(row)};
}

class _StateChip extends StatelessWidget {
  const _StateChip(this.state);

  final BriefState state;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = briefToneColors(state.tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        state.word,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
      ),
    );
  }
}

class _BreakdownRowView extends StatelessWidget {
  const _BreakdownRowView({
    required this.row,
    required this.signed,
    this.whole,
    this.state,
  });

  final BreakdownRow row;
  final bool signed;

  /// This row's points as a whole number from [wholePoints].
  final int? whole;

  /// Words view: shown instead of the points.
  final BriefState? state;

  String get _points {
    final points = row.points;
    if (points == null) return '—';
    if (!signed) return '${whole ?? points.round()}';
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
            if (state case final state?)
              _StateChip(state)
            else
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
