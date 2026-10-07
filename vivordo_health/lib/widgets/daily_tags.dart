import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';

import '../src/services/daily_tags_service.dart';

/// The tags offered for a night, in order. Ids are what's stored.
const dailyTags = <({String id, String label, IconData icon})>[
  (id: 'alcohol', label: 'Alcohol', icon: Icons.wine_bar_outlined),
  (id: 'late_caffeine', label: 'Late caffeine', icon: Icons.coffee_outlined),
  (id: 'late_meal', label: 'Late meal', icon: Icons.restaurant_outlined),
  (
    id: 'screens_in_bed',
    label: 'Screens in bed',
    icon: Icons.phone_iphone_rounded,
  ),
  (id: 'sick', label: 'Sick', icon: Icons.sick_outlined),
  (id: 'travel', label: 'Travel', icon: Icons.flight_rounded),
];

/// "alcohol and late meal", in the offered order.
String dailyTagsPhrase(Set<String> tags) {
  final words = [
    for (final t in dailyTags)
      if (tags.contains(t.id)) t.label.toLowerCase(),
  ];
  return words.length < 2
      ? words.join()
      : '${words.sublist(0, words.length - 1).join(', ')} and ${words.last}';
}

/// One-tap tag chips; tapping toggles.
class DailyTagChips extends StatelessWidget {
  const DailyTagChips({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    const purple = Color(0xFF7F77DD);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final tag in dailyTags)
          if (selected.contains(tag.id) case final on)
            Semantics(
              button: true,
              selected: on,
              child: Material(
                color: on
                    ? (dark
                          ? purple.withValues(alpha: .22)
                          : const Color(0xFFEEEDFE))
                    : Colors.transparent,
                shape: StadiumBorder(
                  side: BorderSide(color: on ? purple : colors.border),
                ),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () => onChanged(
                    on
                        ? ({...selected}..remove(tag.id))
                        : {...selected, tag.id},
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          tag.icon,
                          size: 15,
                          color: on
                              ? (dark
                                    ? const Color(0xFFCECBF6)
                                    : const Color(0xFF3C3489))
                              : colors.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          tag.label,
                          style: TextStyle(
                            fontSize: 12,
                            color: on
                                ? (dark
                                      ? const Color(0xFFCECBF6)
                                      : const Color(0xFF3C3489))
                                : colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
      ],
    );
  }
}

/// A night's tags on their own, to add or fix them after the check-in
/// (Journal). Saves on every tap.
class NightTagsCard extends StatefulWidget {
  const NightTagsCard({super.key, required this.night, required this.title});

  final DateTime night;
  final String title;

  @override
  State<NightTagsCard> createState() => _NightTagsCardState();
}

class _NightTagsCardState extends State<NightTagsCard> {
  Set<String>? _tags;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(NightTagsCard old) {
    super.didUpdateWidget(old);
    if (!DateUtils.isSameDay(old.night, widget.night)) {
      _tags = null;
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final night = widget.night;
    try {
      final tags = await DailyTagsService.load(night);
      if (mounted && DateUtils.isSameDay(night, widget.night)) {
        setState(() => _tags = tags);
      }
    } catch (_) {
      if (mounted) setState(() => _tags = {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final tags = _tags;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withValues(alpha: .07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 11,
              letterSpacing: .7,
            ),
          ),
          const SizedBox(height: 10),
          if (tags == null)
            const SizedBox(height: 32)
          else
            DailyTagChips(
              selected: tags,
              onChanged: (next) {
                setState(() => _tags = next);
                unawaited(
                  DailyTagsService.save(widget.night, next).catchError(
                    (Object e) => debugPrint('Save tags failed: $e'),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
