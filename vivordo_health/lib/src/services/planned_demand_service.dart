import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../utils/day_key.dart';

/// The day's plan as Demand, saved once per day to
/// `users/{uid}/planned_demand/{day}` the first time My Day has it loaded,
/// so the Demand sheet can show planned against what the day took.
class PlannedDemandService {
  const PlannedDemandService._();

  static const version = 1;
  static final _saved = <String>{};

  /// Whether [day] is already saved (or being saved) this session, so My
  /// Day can skip working it out.
  static bool savedThisSession(DateTime day) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid == null || _saved.contains('$uid/${localDayKey(day)}');
  }

  /// Saves [points] for [day] unless that day already has a plan saved:
  /// the first full plan of the day is the one kept. Never throws.
  static Future<void> saveOnce(DateTime day, double points) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final key = '$uid/${localDayKey(day)}';
    if (!_saved.add(key)) return;
    try {
      final doc = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('planned_demand')
          .doc(localDayKey(day));
      if ((await doc.get()).exists) return;
      await doc.set({
        'points': (points * 10).round() / 10,
        'version': version,
        'savedAt': FieldValue.serverTimestamp(),
      });
    } catch (error) {
      // Offline or failed read: try again on a later My Day refresh.
      _saved.remove(key);
      debugPrint('PlannedDemandService: could not save the plan: $error');
    }
  }
}
