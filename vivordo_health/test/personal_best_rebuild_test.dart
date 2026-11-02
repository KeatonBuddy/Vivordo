import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/services/workout_service.dart';

void main() {
  final earlier = Timestamp.fromDate(DateTime(2026, 10, 16, 18));
  final later = Timestamp.fromDate(DateTime(2026, 10, 16, 19));

  test('rebuilds on a new version, or after a newer stale save', () {
    expect(personalBestsNeedRebuild(null, 4), isTrue);
    expect(
      personalBestsNeedRebuild({'personalBestBackfillVersion': 3}, 4),
      isTrue,
      reason: 'existing accounts rebuild once for old offline saves',
    );
    final current = {
      'personalBestBackfillVersion': 4,
      'personalBestBackfilledAt': earlier,
    };
    expect(personalBestsNeedRebuild(current, 4), isFalse);
    expect(
      personalBestsNeedRebuild({...current, 'personalBestsStaleAt': later}, 4),
      isTrue,
      reason: 'a workout saved offline after the last rebuild',
    );
    expect(
      personalBestsNeedRebuild({
        'personalBestBackfillVersion': 4,
        'personalBestBackfilledAt': later,
        'personalBestsStaleAt': earlier,
      }, 4),
      isFalse,
      reason: 'already rebuilt since',
    );
    expect(
      personalBestsNeedRebuild({
        'personalBestBackfillVersion': 4,
        'personalBestsStaleAt': earlier,
      }, 4),
      isTrue,
    );
  });
}
