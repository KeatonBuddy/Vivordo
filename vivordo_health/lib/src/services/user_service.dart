import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:vivordo_health/src/models/questionnaire_response.dart';
import 'package:vivordo_health/src/models/metadata.dart';
import 'package:vivordo_health/src/models/user_model.dart';

class UserService {
  static Future<void> createUser(User authUser) async {
    UserModel firestoreUser = UserModel(
      uid: authUser.uid,
      displayName: authUser.displayName,
      photoUrl: authUser.photoURL,
      email: authUser.email,
      onboardingCompleted: false,
      createdAt: Timestamp.fromDate(authUser.metadata.creationTime as DateTime),
      updatedAt: Timestamp.fromDate(authUser.metadata.creationTime as DateTime),
    );
    await FirebaseFirestore.instance
        .collection('users')
        .doc(authUser.uid)
        .set(firestoreUser.toMap());
  }

  static Future<void> submitQuestionnaire({
    required User? user,
    required Map<String, dynamic> userdata,
  }) async {
    final metadata = Metadata.create().toMap();

    if (user != null) {
      QuestionnaireResponse firestoreResponse = QuestionnaireResponse(
        userId: user.uid,
        questionnaireType: "baseline",
        submittedAt: FieldValue.serverTimestamp(),
        metadata: metadata,
        answers: Map<String, dynamic>.from(userdata["responses"] ?? {}),
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      );

      await FirebaseFirestore.instance
          .collection('questionnaire_responses')
          .add(firestoreResponse.toMap());
    } else {
      throw Exception("User unavailable");
      //TODO: Log this
    }
  }
}
