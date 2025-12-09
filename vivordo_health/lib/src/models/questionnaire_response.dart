import 'dart:ffi';

import 'package:cloud_firestore/cloud_firestore.dart';

class QuestionnaireResponse {
  final String id;
  final String userId;
  String questionnaireType;
  String version;
  Timestamp submittedAt;
  Map<String, dynamic> metadata;
  Map<String, dynamic> answers;
  Map<String, dynamic> derivedScores;
  Timestamp createdAt;
  Timestamp updatedAt;

  QuestionnaireResponse({
    required this.id,
    required this.userId,
    required this.questionnaireType,
    this.version = 'v1',
    required this.submittedAt,
    required this.metadata,
    this.answers = const {},
    this.derivedScores = const {"stressScore": null},
    required this.createdAt,
    required this.updatedAt,
  });

  factory QuestionnaireResponse.fromMap(Map<String, dynamic> data) {
    return QuestionnaireResponse(
      id: data['id'],
      userId: data['userId'],
      questionnaireType: data['questionnaireType'],
      version: data['version'],
      submittedAt: data['submittedAt'],
      metadata: data['metadata'],
      answers: data['answers'],
      derivedScores: data['derivedScores'],
      createdAt: data['createdAt'],
      updatedAt: data['updatedAt'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'questionnaireType': questionnaireType,
      'version': version,
      'submittedAt': submittedAt,
      'metadata': metadata,
      'answers': answers,
      'derivedScores': derivedScores,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  void addAnswer(String questionID, dynamic answer) {
    answers[questionID] = answer;
  }

  void changeStressScore(Float score) {
    derivedScores["stressScore"] = score;
  }

  Future<void> toFirestore() async {
    FirebaseFirestore.instance.collection('questionnare_response').add(toMap());
  }
}
