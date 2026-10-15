import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/screens/onboarding_flow_screen.dart';
import 'package:vivordo_health/src/utils/home_stress_card_logic.dart';
import 'package:vivordo_health/src/utils/metrics_insights.dart';
import 'package:vivordo_health/src/utils/day_key.dart';
import 'package:vivordo_health/src/utils/stress_view.dart';
import 'package:vivordo_health/widgets/daily_brief_card.dart';
import 'package:vivordo_health/widgets/home_stress_card.dart';

/// Words mode (Settings → Show score numbers off): scores as sentences and
/// states, measurements kept.
void main() {
  test('stress in words: a sentence per level, around the person\'s usual', () {
    expect(homeStressSentence(20), 'Calm');
    expect(homeStressSentence(38), 'Calmer than usual');
    expect(homeStressSentence(47), 'Steady');
    expect(homeStressSentence(70), 'Quite tense');
    expect(homeStressSentence(90), 'Very tense');
    expect(homeStressSentence(null), isNull);
    // The bands move with the person's usual.
    expect(homeStressSentence(40, usual: 35), 'Steady');
    expect(homeStressSentence(40, usual: 65), 'Calm');
    expect(stressUsualHeadlineWords(58, 50), 'Higher than usual');
    expect(stressUsualHeadlineWords(52, 50), 'About usual');
  });

  test('the stress trend in a sentence', () {
    StressDay day(int d, double average) =>
        StressDay(date: DateTime(2026, 10, d), average: average);
    final calm = day(6, 20), tense = day(7, 70);
    expect(
      stressTrendSentence(
        StressTrendStats(
          average: 40,
          calmest: calm,
          hardest: tense,
          change: -8,
        ),
        'last week',
      ),
      'Calmest on Tuesday, most tense on Wednesday. Calmer than last week.',
    );
  });

  test('the brief as states', () {
    expect(
      briefEnergyState(capacity: 60, usual: 72, recovering: false).word,
      'Lower than usual',
    );
    expect(
      briefEnergyState(capacity: 74, usual: 72, recovering: false).word,
      'Your usual',
    );
    expect(
      briefEnergyState(capacity: 74, usual: null, recovering: false).word,
      'Moderate',
    );
    expect(
      briefEnergyState(capacity: 74, usual: 72, recovering: true).word,
      'Recovering',
    );
    expect(
      briefEnergyState(capacity: null, usual: 72, recovering: false).word,
      'Needs health data',
    );
    expect(
      briefEnergyState(
        capacity: null,
        usual: 72,
        recovering: false,
        emptyWord: 'After you sleep',
      ).word,
      'After you sleep',
    );
    // Why Capacity is empty, in order of what's true.
    String label({
      bool before = false,
      bool slept = false,
      bool tracks = false,
    }) => capacityEmptyState(
      beforeSleep: before,
      sleepRecorded: slept,
      tracksSleep: tracks,
    ).label;
    expect(label(before: true, tracks: true), 'Ready after you sleep');
    expect(label(slept: true, tracks: true), 'Working it out');
    expect(label(tracks: true), 'Waiting for sleep · check in now');
    expect(label(), 'Connect Health or check in');
    expect(
      capacityEmptyState(
        beforeSleep: false,
        sleepRecorded: false,
        tracksSleep: true,
      ).footer,
      "Waiting for last night's sleep",
    );
    expect(briefLoadState(demand: 40, capacity: 70).word, 'Light');
    expect(briefLoadState(demand: 70, capacity: 70).word, 'Full');
    expect(briefLoadState(demand: 90, capacity: 70).word, 'Heavy');
    expect(briefLoadState(demand: null, capacity: 70).word, 'Loading');
    expect(
      briefLoadState(demand: null, capacity: 70, planFailed: true).word,
      "Didn't load",
    );
  });

  test('Metrics insights drop the scores', () {
    final today = DateTime(2026, 10, 11);
    final days = {
      for (var i = 0; i < 35; i++)
        localDayKey(DateTime(2026, 10, 11 - i)): {
          'capacity': {'score': i < 7 ? 55 : 75},
        },
    };
    final words = metricsInsights(days, today, numbers: false);
    final numbers = metricsInsights(days, today);
    expect(
      words.map((i) => i.text),
      contains('Your energy has been lower than usual this week.'),
    );
    expect(numbers.map((i) => i.text), contains(contains('averaged 55')));
  });

  test('onboarding asks about scores before notifications', () {
    final steps = onboardingSteps(const {});
    expect(
      steps.indexOf(OnboardingStep.scores),
      steps.indexOf(OnboardingStep.notifications) - 1,
    );
  });

  testWidgets('Home stress card: a sentence and chip, no ring or percent', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeStressCard(
            score: 47,
            updatedAt: DateTime(2026, 10, 11, 9),
            usual: 48,
            drivers: const [],
            steps: 1200,
            loading: false,
            updating: false,
            revealScore: true,
            onInfoTap: () {},
            showNumbers: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Steady'), findsOneWidget);
    expect(find.text('Moderate'), findsOneWidget);
    expect(find.text('About usual'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
    expect(find.text('STRESS'), findsNothing);
  });

  testWidgets('My Day brief: state rows instead of rings', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DailyBriefCard(
              headline: 'Room to spare today',
              summary: 'Slept about your usual.',
              capacityScore: 62,
              capacityLabel: 'Below your usual',
              scheduleScore: 30,
              scheduleLabel: 'Remaining today',
              footer: 'Available data',
              words: (
                energy: (word: 'Lower than usual', tone: BriefTone.low),
                loadTitle: "Today's load",
                load: (word: 'Light', tone: BriefTone.good),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Energy'), findsOneWidget);
    expect(find.text('Lower than usual'), findsOneWidget);
    expect(find.text("Today's load"), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('62'), findsNothing);
    expect(find.text('30'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
