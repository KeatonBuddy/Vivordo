import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'ai_consent.dart';

/// A calendar event to sort: title only, never notes.
typedef PlanEventInput = ({String title, int minutes, int attendees});

/// Claude's estimate for a priority: 'light', 'moderate' or 'demanding',
/// and minutes when the title gives an idea.
typedef PriorityEstimate = ({String effort, int? minutes});

/// Sorts calendar events the local rules can't classify, and estimates
/// effort and duration for priorities saved without them, through the
/// `classifyPlanItems` function (functions/plan_classifier.js). Nothing is
/// sent without the signed-in user's AI consent.
class PlanClassifier {
  PlanClassifier._();

  static final _fn = FirebaseFunctions.instance.httpsCallable(
    'classifyPlanItems',
  );

  /// Categories by index into [events], estimates by index into
  /// [priorityTitles]. Null without consent.
  static Future<
    ({Map<int, String> events, Map<int, PriorityEstimate> priorities})?
  >
  classify({
    List<PlanEventInput> events = const [],
    List<String> priorityTitles = const [],
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || !await AiConsent.granted(uid)) return null;
    final result = await _fn
        .call<dynamic>({
          'events': [
            for (final (i, e) in events.indexed)
              {
                'id': 'e$i',
                'title': e.title,
                'minutes': e.minutes,
                'attendees': e.attendees,
              },
          ],
          'priorities': [
            for (final (i, title) in priorityTitles.indexed)
              {'id': 'p$i', 'title': title},
          ],
        })
        .timeout(const Duration(seconds: 30));
    final data = result.data as Map? ?? const {};
    int? index(Object? id, String prefix) =>
        id is String && id.startsWith(prefix)
        ? int.tryParse(id.substring(1))
        : null;
    return (
      events: {
        for (final item
            in (data['events'] as List? ?? const []).whereType<Map>())
          if (index(item['id'], 'e') case final i?
              when item['category'] is String)
            i: item['category'] as String,
      },
      priorities: {
        for (final item
            in (data['priorities'] as List? ?? const []).whereType<Map>())
          if (index(item['id'], 'p') case final i?
              when const {
                'light',
                'moderate',
                'demanding',
              }.contains(item['effort']))
            i: (
              effort: item['effort'] as String,
              minutes: (item['minutes'] as num?)?.toInt(),
            ),
      },
    );
  }
}
