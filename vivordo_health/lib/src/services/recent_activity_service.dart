import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class RecentActivity {
  const RecentActivity({
    required this.id,
    required this.name,
    required this.minutes,
    required this.day,
    this.km,
    this.sets,
  });

  final String id;
  final String name;
  final int minutes;
  final DateTime day;
  final double? km;
  final int? sets;

  factory RecentActivity.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    return RecentActivity(
      id: document.id,
      name: data['name'] as String? ?? 'Activity',
      minutes: (data['minutes'] as num?)?.round() ?? 0,
      day: (data['day'] as Timestamp?)?.toDate() ?? DateTime.now(),
      km: (data['km'] as num?)?.toDouble(),
      sets: (data['sets'] as num?)?.round(),
    );
  }
}

class RecentActivityService {
  const RecentActivityService._();

  static CollectionReference<Map<String, dynamic>>? _collection() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('recent_activities');
  }

  static Stream<List<RecentActivity>> watch({int limit = 20}) {
    final collection = _collection();
    if (collection == null) return Stream.value(const []);
    return collection
        .orderBy('day', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(RecentActivity.fromDocument)
              .toList(growable: false),
        );
  }

  static Future<void> add({
    required String name,
    required int minutes,
    required DateTime day,
    double? km,
    int? sets,
  }) async {
    final collection = _collection();
    if (collection == null) {
      throw StateError('Sign in before logging an activity.');
    }
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) throw ArgumentError('Activity name is required.');
    if (minutes <= 0) throw ArgumentError('Minutes must be greater than zero.');

    await collection.add({
      'name': trimmedName,
      'minutes': minutes,
      'day': Timestamp.fromDate(day),
      'km': km,
      'sets': sets,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
