import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/widgets/crisis_support_card.dart';

void main() {
  test('crisis phrases are detected, including iOS curly apostrophes', () {
    for (final text in [
      'I keep thinking about suicide',
      'honestly I want to die',
      'I wanna die',
      'I don’t want to live like this',
      "I don't want to be alive",
      'I have been self-harming again',
      'I cut myself last night',
      'I keep thinking about hurting myself',
      'cutting myself again',
      'thinking of ending my life',
      'I took an overdose',
    ]) {
      expect(mentionsCrisis(text), isTrue, reason: text);
    }
  });

  test('ordinary stress talk is not flagged', () {
    for (final text in [
      'this deadline is killing me',
      'I want to end my day early',
      'my workout nearly killed me lol',
      'I am so tired of meetings',
    ]) {
      expect(mentionsCrisis(text), isFalse, reason: text);
    }
  });

  test('crisis line follows the device region', () {
    expect(crisisLineFor('us')?.uri.toString(), 'tel:988');
    expect(crisisLineFor('CA')?.uri.toString(), 'tel:988');
    expect(crisisLineFor('GB')?.uri.toString(), 'tel:116123');
    expect(crisisLineFor('AU')?.uri.toString(), 'tel:131114');
    expect(crisisLineFor('DE'), isNull);
    expect(crisisLineFor(null), isNull);
  });
}
