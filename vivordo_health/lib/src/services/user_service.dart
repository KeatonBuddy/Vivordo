import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:vivordo_health/src/models/goals.dart';
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

  //create goal
  //TODO: update goal - with 1 get goal defoposit
  //TODO: get goal - get with 1 autoid
  //TODO: get all goals - query for all

  static Future<void> createGoal({
    required User theUser,
    required String userId,
    required String title,
    required String status,
    String? description,
    String? category,
    String? targetMetricType,
    double? targetValue,
    String? targetUnit,
    String? direction,
    String? endDate,
    String? progressCurrentValue,
    String? progressCompletionPercent,
  }) async {
    Map<String, dynamic>? progress;
    if (progressCurrentValue != null) {
      progress = {
        "currentValue": progressCurrentValue,
        "completionPercent": progressCompletionPercent,
        "lastUpdated": FieldValue.serverTimestamp(),
      };
    }

    Goals newGoal = Goals(
      userId: theUser.uid,
      title: title,
      description: description,
      category: category,
      targetMetricType: targetMetricType,
      targetValue: targetValue,
      targetUnit: targetUnit,
      direction: direction,
      startDate: FieldValue.serverTimestamp().toString(),
      endDate: endDate,
      status: status,
      progress: progress,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    );

    await FirebaseFirestore.instance.collection('goals').add(newGoal.toMap());
  }

  static Future<void> submitQuestionare(Map<String, dynamic> userdata) async {
    User? authUser = FirebaseAuth.instance.currentUser;
    final metadata = Metadata.create().toMap();

    if (authUser != null) {
      QuestionnaireResponse firestoreResponse = QuestionnaireResponse(
        userId: authUser.uid,
        questionnaireType: "baseline",
        submittedAt: FieldValue.serverTimestamp(),
        metadata: metadata,
        answers: userdata["responses"],
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      );

      await FirebaseFirestore.instance
          .collection('questionnaire_responses')
          .add(firestoreResponse.toMap());
    } else {
      print("Error: User is null");
    }
  }
}
