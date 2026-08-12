import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CircleChallengeMembership {
  const CircleChallengeMembership({
    required this.challengeId,
    required this.creatorUid,
    required this.creatorName,
    required this.type,
    required this.title,
    required this.message,
    required this.unit,
    required this.role,
    required this.status,
    required this.goal,
    required this.progress,
    required this.totalProgress,
    required this.durationDays,
    required this.participantUids,
    required this.createdAt,
    this.startAt,
    this.endAt,
  });

  factory CircleChallengeMembership.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) => CircleChallengeMembership._fromData(
    snapshot.id,
    snapshot.data() ?? const <String, dynamic>{},
  );

  factory CircleChallengeMembership.fromChallengeSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot, {
    required String userId,
    Map<String, dynamic>? participantData,
  }) {
    final challenge = snapshot.data() ?? const <String, dynamic>{};
    final creatorUid = challenge['creatorUid'] as String? ?? '';
    final pendingUids = (challenge['pendingUids'] as List? ?? const [])
        .whereType<String>()
        .toSet();
    final acceptedUids = (challenge['acceptedUids'] as List? ?? const [])
        .whereType<String>()
        .toSet();
    final declinedUids = (challenge['declinedUids'] as List? ?? const [])
        .whereType<String>()
        .toSet();
    final challengeStatus = challenge['status'] as String? ?? 'pending';
    final participantStatus = participantData?['status'] as String?;

    final status = switch (challengeStatus) {
      'pending' when pendingUids.contains(userId) => 'pending',
      'pending' when acceptedUids.contains(userId) => 'waiting',
      'active' when participantStatus == 'completed' => 'completed',
      'active' when acceptedUids.contains(userId) => 'active',
      _ when declinedUids.contains(userId) => 'declined',
      _ => challengeStatus,
    };

    return CircleChallengeMembership._fromData(snapshot.id, {
      ...challenge,
      'role': creatorUid == userId ? 'creator' : 'participant',
      'status': status,
      'progress': participantData?['progress'] ?? 0,
    });
  }

  factory CircleChallengeMembership._fromData(
    String challengeId,
    Map<String, dynamic> data,
  ) {
    DateTime? date(String key) => (data[key] as Timestamp?)?.toDate();
    return CircleChallengeMembership(
      challengeId: challengeId,
      creatorUid: data['creatorUid'] as String? ?? '',
      creatorName: data['creatorName'] as String? ?? 'Circle friend',
      type: data['type'] as String? ?? '',
      title: data['title'] as String? ?? 'Challenge',
      message: data['message'] as String? ?? '',
      unit: data['unit'] as String? ?? '',
      role: data['role'] as String? ?? 'participant',
      status: data['status'] as String? ?? 'pending',
      goal: (data['goal'] as num?)?.toInt() ?? 0,
      progress:
          (data['progress'] as num?)?.toInt() ??
          (data['totalProgress'] as num?)?.toInt() ??
          0,
      totalProgress: (data['totalProgress'] as num?)?.toInt() ?? 0,
      durationDays: (data['durationDays'] as num?)?.toInt() ?? 1,
      participantUids: (data['participantUids'] as List? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      createdAt: date('createdAt') ?? DateTime.fromMillisecondsSinceEpoch(0),
      startAt: date('startAt'),
      endAt: date('endAt'),
    );
  }

  final String challengeId;
  final String creatorUid;
  final String creatorName;
  final String type;
  final String title;
  final String message;
  final String unit;
  final String role;
  final String status;
  final int goal;
  final int progress;
  final int totalProgress;
  final int durationDays;
  final List<String> participantUids;
  final DateTime createdAt;
  final DateTime? startAt;
  final DateTime? endAt;

  bool get isInvite => status == 'pending';
  bool get isOngoing => status == 'waiting' || status == 'active';
}

class CircleChallengeParticipant {
  const CircleChallengeParticipant({
    required this.uid,
    required this.username,
    required this.role,
    required this.status,
    required this.progress,
  });

  factory CircleChallengeParticipant.fromSnapshot(
    QueryDocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    return CircleChallengeParticipant(
      uid: snapshot.id,
      username: data['username'] as String? ?? 'Circle member',
      role: data['role'] as String? ?? 'participant',
      status: data['status'] as String? ?? 'pending',
      progress: (data['progress'] as num?)?.toInt() ?? 0,
    );
  }

  final String uid;
  final String username;
  final String role;
  final String status;
  final int progress;
}

class CircleChallengeContribution {
  const CircleChallengeContribution({
    required this.uid,
    required this.sourceType,
    required this.sourceId,
    required this.value,
    required this.occurredAt,
  });

  factory CircleChallengeContribution.fromSnapshot(
    QueryDocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    final timestamp =
        data['occurredAt'] as Timestamp? ?? data['updatedAt'] as Timestamp?;
    return CircleChallengeContribution(
      uid: data['uid'] as String? ?? '',
      sourceType: data['sourceType'] as String? ?? '',
      sourceId: data['sourceId'] as String? ?? snapshot.id,
      value: (data['value'] as num?)?.toInt() ?? 0,
      occurredAt: timestamp?.toDate(),
    );
  }

  final String uid;
  final String sourceType;
  final String sourceId;
  final int value;
  final DateTime? occurredAt;
}

class CircleChallengeDetails {
  const CircleChallengeDetails({
    required this.participants,
    required this.contributions,
  });

  final List<CircleChallengeParticipant> participants;
  final List<CircleChallengeContribution> contributions;
}

class CircleChallengeComment {
  const CircleChallengeComment({
    required this.id,
    required this.authorUid,
    required this.text,
    required this.createdAt,
  });

  factory CircleChallengeComment.fromSnapshot(
    QueryDocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    return CircleChallengeComment(
      id: snapshot.id,
      authorUid: data['authorUid'] as String? ?? '',
      text: data['text'] as String? ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  final String id;
  final String authorUid;
  final String text;
  final DateTime? createdAt;
}

class CircleChallengeService {
  CircleChallengeService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseFunctions _functions = FirebaseFunctions.instance;

  static Stream<List<CircleChallengeMembership>> watchMemberships() =>
      FirebaseAuth.instance.userChanges().asyncExpand((user) {
        if (user == null) return Stream.value(const []);
        return _firestore
            .collection('challenges')
            .where('participantUids', arrayContains: user.uid)
            .snapshots()
            .asyncMap((snapshot) async {
              final memberships = await Future.wait(
                snapshot.docs.map((challenge) async {
                  final membership = await _firestore
                      .collection('challenge_memberships')
                      .doc(user.uid)
                      .collection('items')
                      .doc(challenge.id)
                      .get();
                  if (membership.exists) {
                    return CircleChallengeMembership.fromSnapshot(membership);
                  }

                  final participant = await challenge.reference
                      .collection('participants')
                      .doc(user.uid)
                      .get();
                  return CircleChallengeMembership.fromChallengeSnapshot(
                    challenge,
                    userId: user.uid,
                    participantData: participant.data(),
                  );
                }),
              );
              memberships.sort((a, b) => b.createdAt.compareTo(a.createdAt));
              return List<CircleChallengeMembership>.unmodifiable(memberships);
            });
      });

  static Future<String> create({
    required String type,
    required int goal,
    required int durationDays,
    required List<String> participantUids,
    String? targetName,
    String? message,
  }) async {
    final payload = <String, dynamic>{
      'type': type,
      'goal': goal,
      'durationDays': durationDays,
      'participantUids': participantUids,
    };
    final trimmedTargetName = targetName?.trim();
    if (trimmedTargetName != null && trimmedTargetName.isNotEmpty) {
      payload['targetName'] = trimmedTargetName;
    }
    final trimmedMessage = message?.trim();
    if (trimmedMessage != null && trimmedMessage.isNotEmpty) {
      payload['message'] = trimmedMessage;
    }
    final result = await _functions
        .httpsCallable('createChallenge')
        .call(payload);
    final data = Map<String, dynamic>.from(result.data as Map);
    return data['challengeId'] as String;
  }

  static Future<void> respond({
    required String challengeId,
    required bool accept,
  }) async {
    await _functions.httpsCallable('respondToChallenge').call({
      'challengeId': challengeId,
      'accept': accept,
    });
  }

  static Future<void> cancel(String challengeId) async {
    await _functions.httpsCallable('cancelChallenge').call({
      'challengeId': challengeId,
    });
  }

  static Future<CircleChallengeDetails> loadDetails(String challengeId) async {
    final challenge = _firestore.collection('challenges').doc(challengeId);
    final results = await Future.wait([
      challenge.collection('participants').get(),
      challenge
          .collection('contributions')
          .orderBy('updatedAt', descending: true)
          .limit(20)
          .get(),
    ]);
    final participantSnapshot = results[0];
    final contributionSnapshot = results[1];
    final participants = participantSnapshot.docs
        .map(CircleChallengeParticipant.fromSnapshot)
        .toList(growable: false);
    final contributions = contributionSnapshot.docs
        .map(CircleChallengeContribution.fromSnapshot)
        .toList(growable: false);
    return CircleChallengeDetails(
      participants: participants,
      contributions: contributions,
    );
  }

  static Stream<List<CircleChallengeComment>> watchComments(
    String challengeId,
  ) => _firestore
      .collection('challenges')
      .doc(challengeId)
      .collection('comments')
      .orderBy('createdAt')
      .limit(100)
      .snapshots()
      .map(
        (snapshot) => List<CircleChallengeComment>.unmodifiable(
          snapshot.docs.map(CircleChallengeComment.fromSnapshot),
        ),
      );

  static Future<void> addComment({
    required String challengeId,
    required String text,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final trimmed = text.trim();
    if (user == null) throw StateError('You must be signed in to comment.');
    if (trimmed.isEmpty || trimmed.length > 500) {
      throw ArgumentError('Comments must be between 1 and 500 characters.');
    }
    await _firestore
        .collection('challenges')
        .doc(challengeId)
        .collection('comments')
        .add({
          'authorUid': user.uid,
          'text': trimmed,
          'createdAt': FieldValue.serverTimestamp(),
        });
  }

  static Future<void> deleteComment({
    required String challengeId,
    required String commentId,
  }) => _firestore
      .collection('challenges')
      .doc(challengeId)
      .collection('comments')
      .doc(commentId)
      .delete();
}
