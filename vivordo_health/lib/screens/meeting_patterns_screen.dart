import 'package:flutter/material.dart';

import '../src/services/meeting_patterns_service.dart';
import '../src/utils/heavy_days.dart';
import '../src/utils/meeting_patterns.dart';
import '../theme/vivordo_theme.dart';
import '../widgets/meeting_patterns_view.dart';

/// Which meetings tend to run your heart rate high or keep it calm, and
/// what heavy meeting days do to your sleep and next morning.
class MeetingPatternsScreen extends StatefulWidget {
  const MeetingPatternsScreen({super.key});

  @override
  State<MeetingPatternsScreen> createState() => _MeetingPatternsScreenState();
}

class _MeetingPatternsScreenState extends State<MeetingPatternsScreen> {
  late final _load = MeetingPatternsService.load();

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    TextStyle secondary([double size = 13]) =>
        TextStyle(fontSize: size, height: 1.4, color: colors.textSecondary);
    Widget section(String title) => Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          letterSpacing: 1.1,
          fontWeight: FontWeight.w700,
          color: colors.textSecondary,
        ),
      ),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Meeting patterns')),
      body: FutureBuilder(
        future: _load,
        builder: (context, snapshot) {
          final data = snapshot.data;
          if (data == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final p = data.patterns;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
            children: [
              Text(
                'Your heart rate during events against your usual at that '
                'time of day, over the last 90 days · ${p.measured} events '
                'measured.',
                style: secondary(),
              ),
              if (p.learning) ...[
                const SizedBox(height: 18),
                _Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Learning which meetings get to you',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Vivordo needs your watch\'s heart rate during a few '
                        'weeks of events before it can say anything honest. '
                        'A repeating meeting needs 4 measured times; a kind '
                        'of meeting needs 8.',
                        style: secondary(),
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: p.progress,
                          minHeight: 6,
                          color: const Color(0xFF7F77DD),
                          backgroundColor: colors.cardMuted,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${p.measured} of about '
                        '${MeetingPatterns.learningTarget} events',
                        style: secondary(12),
                      ),
                    ],
                  ),
                ),
              ],
              if (p.high.isNotEmpty) ...[
                section('RAISE YOUR HEART RATE MOST'),
                _Card(child: _PatternList(p.high)),
              ],
              if (p.calm.isNotEmpty) ...[
                section('KEEP IT LOWEST'),
                _Card(child: _PatternList(p.calm)),
              ],
              section('HEAVY MEETING DAYS'),
              _Card(child: _HeavyDaysView(data.heavy)),
              const SizedBox(height: 18),
              Text(
                'A wellness estimate, not a measure of stress: coffee, '
                'walking between rooms or excitement raise heart rate too. '
                'Exercise isn\'t counted.',
                style: secondary(11),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.vivordoColors.card,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: context.vivordoColors.border),
    ),
    child: child,
  );
}

class _PatternList extends StatelessWidget {
  const _PatternList(this.patterns);

  final List<MeetingPattern> patterns;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return Column(
      children: [
        for (final p in patterns)
          InkWell(
            onTap: () => showMeetingPatternSheet(
              context,
              title: MeetingPatternsService.nameOf(p),
              pattern: p,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: patternStyle(p).accent.withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      patternStyle(p).icon,
                      size: 18,
                      color: patternStyle(p).accent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          MeetingPatternsService.nameOf(p),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${p.liftLabel} · ${p.countLabel}',
                          style: TextStyle(
                            fontSize: 13,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: colors.textSecondary,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _HeavyDaysView extends StatelessWidget {
  const _HeavyDaysView(this.heavy);

  final HeavyDays heavy;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final secondary = TextStyle(
      fontSize: 13,
      height: 1.4,
      color: colors.textSecondary,
    );
    if (!heavy.ready) {
      return Text(
        'Days with 4+ hours of events, compared with your other weekdays. '
        'Needs 6 heavy days and 10 lighter ones · ${heavy.heavy} heavy and '
        '${heavy.other} lighter so far.',
        style: secondary,
      );
    }
    Widget row(String label, String value, bool worse) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 15, color: colors.textPrimary),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: worse ? const Color(0xFFE0703F) : colors.textPrimary,
            ),
          ),
        ],
      ),
    );
    final sleep = heavy.sleepMinutes?.round();
    final capacity = heavy.capacity?.round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Days with 4+ hours of events, against your other weekdays.',
          style: secondary,
        ),
        const SizedBox(height: 6),
        if (sleep != null)
          row(
            'Sleep that night',
            sleep.abs() < 5
                ? 'About the same'
                : '${sleep.abs()} min ${sleep < 0 ? 'shorter' : 'longer'}',
            sleep <= -5,
          ),
        if (capacity != null)
          row(
            'Capacity next morning',
            capacity.abs() < 2
                ? 'About the same'
                : '${capacity.abs()} points ${capacity < 0 ? 'lower' : 'higher'}',
            capacity <= -2,
          ),
        const SizedBox(height: 4),
        Text(
          'From ${heavy.heavy} heavy days and ${heavy.other} lighter ones. '
          'Small samples can mislead; this updates as more days come in.',
          style: secondary.copyWith(fontSize: 12),
        ),
      ],
    );
  }
}
