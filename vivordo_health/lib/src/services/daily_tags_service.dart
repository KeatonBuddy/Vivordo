import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../utils/day_key.dart';

/// One-tap tags for a night (alcohol, a late meal…), saved in
/// `users/{uid}/daily_tags/{day}` under the date the evening belongs to, so
/// they line up with that night's sleep and the next day's Capacity. Kept
/// out of metrics_daily: a tap there would resend the large day documents
/// to every open listener.
///
/// A saved empty list means "nothing that night", which comparisons need as
/// much as the tags: it's saved whenever sleep is rated with the tags in view.
class DailyTagsService {
  static DocumentReference<Map<String, dynamic>>? _doc(DateTime night) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('daily_tags')
        .doc(localDayKey(night));
  }

  /// The night's tags; empty when none were saved.
  static Future<Set<String>> load(DateTime night) async {
    final data = (await _doc(night)?.get())?.data();
    return {...(data?['tags'] as List? ?? const []).whereType<String>()};
  }

  static Future<void> save(DateTime night, Set<String> tags) async =>
      _doc(night)?.set({
        'tags': tags.toList()..sort(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
}
