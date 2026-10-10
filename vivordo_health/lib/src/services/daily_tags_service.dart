import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../utils/day_key.dart';
import '../utils/energy_factors.dart';

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

  static Future<void> save(DateTime night, Set<String> tags) async {
    await _doc(night)?.set({
      'tags': tags.toList()..sort(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _factors = null;
  }

  static Future<List<EnergyFactor>>? _factors;
  static String? _factorsFor;

  /// What shapes [today]'s energy forecast: last night's tags, compared
  /// with your mornings after the last four weeks' nights, and yesterday's
  /// training. Shared by Home and My Day; reloaded after tags are saved.
  static Future<List<EnergyFactor>> energyFactorsFor(DateTime today) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Future.value(const []);
    final day = DateTime(today.year, today.month, today.day);
    final key = '$uid:${localDayKey(day)}';
    if (_factors != null && _factorsFor == key) return _factors!;
    _factorsFor = key;
    return _factors = _loadFactors(uid, day).catchError((Object error) {
      debugPrint('Energy factors unavailable: $error');
      _factors = null;
      return const <EnergyFactor>[];
    });
  }

  static Future<List<EnergyFactor>> _loadFactors(
    String uid,
    DateTime day,
  ) async {
    final user = FirebaseFirestore.instance.collection('users').doc(uid);
    final from = localDayKey(DateTime(day.year, day.month, day.day - 29));
    final to = localDayKey(day);
    Future<QuerySnapshot<Map<String, dynamic>>> range(String name) => user
        .collection(name)
        .where(FieldPath.documentId, isGreaterThanOrEqualTo: from)
        .where(FieldPath.documentId, isLessThanOrEqualTo: to)
        .get();
    final [tags, scores] = await Future.wait([
      range('daily_tags'),
      range('scores_daily'),
    ]);
    return energyFactors(
      today: day,
      tagsByNight: {
        for (final d in tags.docs)
          d.id: {
            ...(d.data()['tags'] as List? ?? const []).whereType<String>(),
          },
      },
      scores: {for (final d in scores.docs) d.id: d.data()},
    );
  }
}
