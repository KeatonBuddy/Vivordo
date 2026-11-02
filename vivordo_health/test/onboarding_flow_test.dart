import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/screens/onboarding_flow_screen.dart';

void main() {
  test('everyone without the current version goes through onboarding', () {
    expect(needsOnboarding(null), isTrue);
    expect(needsOnboarding({'onboardingCompleted': true}), isTrue);
    expect(needsOnboarding({'onboardingVersion': 1}), isTrue);
    expect(needsOnboarding({'onboardingVersion': kOnboardingVersion}), isFalse);
  });

  test('only people who finished the old onboarding see the intro', () {
    final returning = onboardingSteps({'onboardingCompleted': true});
    final fresh = onboardingSteps({'onboardingCompleted': false});
    expect(returning.first, OnboardingStep.intro);
    expect(fresh, isNot(contains(OnboardingStep.intro)));
    expect(fresh.first, OnboardingStep.about);
    expect(fresh.last, OnboardingStep.history);
  });

  test('onboarding is short; the rest is optional setup afterwards', () {
    expect(onboardingSteps(const {}), [
      OnboardingStep.about,
      OnboardingStep.health,
      OnboardingStep.history,
    ]);
    // Every other step is offered after onboarding, none twice.
    expect(
      {...onboardingSteps({'onboardingCompleted': true}), ...setupSteps},
      OnboardingStep.values.toSet(),
    );
    expect(setupSteps, isNot(contains(OnboardingStep.history)));
  });
}
