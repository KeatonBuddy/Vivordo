import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PersonalProfile {
  const PersonalProfile({
    this.heightCm,
    this.weightKg,
    this.bodyFatPercent,
    this.updatedAt,
  });

  final double? heightCm;
  final double? weightKg;
  final double? bodyFatPercent;
  final DateTime? updatedAt;

  factory PersonalProfile.fromUserData(Map<String, dynamic>? data) {
    final preferences = data?['preferences'] as Map?;
    final profile = preferences?['personalProfile'] as Map?;
    return PersonalProfile(
      heightCm: (profile?['heightCm'] as num?)?.toDouble(),
      weightKg: (profile?['weightKg'] as num?)?.toDouble(),
      bodyFatPercent: (profile?['bodyFatPercent'] as num?)?.toDouble(),
      updatedAt: (profile?['updatedAt'] as Timestamp?)?.toDate(),
    );
  }
}

class PersonalProfileMeasurement {
  const PersonalProfileMeasurement({
    required this.recordedAt,
    this.heightCm,
    this.weightKg,
    this.bodyFatPercent,
  });

  final DateTime recordedAt;
  final double? heightCm;
  final double? weightKg;
  final double? bodyFatPercent;

  factory PersonalProfileMeasurement.fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    return PersonalProfileMeasurement(
      recordedAt:
          (data['recordedAt'] as Timestamp?)?.toDate() ??
          DateTime.tryParse(document.id) ??
          DateTime.now(),
      heightCm: (data['heightCm'] as num?)?.toDouble(),
      weightKg: (data['weightKg'] as num?)?.toDouble(),
      bodyFatPercent: (data['bodyFatPercent'] as num?)?.toDouble(),
    );
  }
}

class PersonalProfileService {
  const PersonalProfileService._();

  static Stream<PersonalProfile> watch() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value(const PersonalProfile());
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .map((snapshot) => PersonalProfile.fromUserData(snapshot.data()));
  }

  static Stream<List<PersonalProfileMeasurement>> watchMeasurements() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value(const []);
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('personal_profile_measurements')
        .orderBy('recordedAt')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(PersonalProfileMeasurement.fromDocument)
              .toList(growable: false),
        );
  }

  static Future<void> save({
    required double heightCm,
    required double weightKg,
    double? bodyFatPercent,
    DateTime? recordedAt,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Sign in before saving your profile.');
    final db = FirebaseFirestore.instance;
    final userReference = db.collection('users').doc(user.uid);
    final measurementReference = userReference
        .collection('personal_profile_measurements')
        .doc();
    final batch = db.batch();
    batch.set(userReference, {
      'preferences': {
        'personalProfile': {
          'heightCm': heightCm,
          'weightKg': weightKg,
          'bodyFatPercent': ?bodyFatPercent,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      },
    }, SetOptions(merge: true));
    batch.set(measurementReference, {
      'heightCm': heightCm,
      'weightKg': weightKg,
      'bodyFatPercent': ?bodyFatPercent,
      'recordedAt': Timestamp.fromDate(recordedAt ?? DateTime.now()),
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }
}
