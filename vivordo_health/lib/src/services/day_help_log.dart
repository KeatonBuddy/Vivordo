import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../utils/day_key.dart';

/// Ways Vivordo helped plan a day besides My Day's fixes, which log
/// themselves. Counted by the recap shown when access ends
/// (access_recap.dart).
enum DayHelp { planMyDay, vivordoAi }

/// Days already marked this session, so a long chat writes once a day.
final _marked = <String>{};

/// Marks today on its day_fixes entry (`helped.<how>`), next to the fixes,
/// so the recap reads one collection.
Future<void> markDayHelped(DayHelp how) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  final day = localDayKey(DateTime.now());
  if (!_marked.add('$uid:$day:${how.name}')) return;
  try {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('day_fixes')
        .doc(day)
        .set({
          'helped': {how.name: true},
        }, SetOptions(merge: true));
  } catch (_) {
    // The recap counts one day fewer; nothing the person sees changes.
    _marked.remove('$uid:$day:${how.name}');
  }
}
