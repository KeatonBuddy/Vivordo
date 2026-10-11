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
    expect(fresh.last, OnboardingStep.notifications);
  });
}
