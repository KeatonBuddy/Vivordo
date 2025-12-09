import 'dart:core';
import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  String? displayName;
  String? email;
  String? photoUrl;
  String? orgId;
  List<String>? roles;
  bool onboardingCompleted;
  Timestamp? onboardingCompletedAt;
  Map<String, dynamic>? preferences; //should we create models for these?
  Map<String, dynamic>? homeConfig; //create model?
  final Timestamp? createdAt;
  Timestamp? updatedAt;

  UserModel({
    required this.uid,
    required this.displayName,
    required this.email,
    required this.onboardingCompleted,
    required this.createdAt,
    required this.updatedAt,
    this.photoUrl,
    this.orgId,
    this.roles,
    this.onboardingCompletedAt,
    this.homeConfig,
    this.preferences,
  });

  factory UserModel.fromMap(Map<String, dynamic> firestoreData, String id) {
    return UserModel(
      uid: id,
      displayName: firestoreData['displayName'],
      email: firestoreData['email'],
      onboardingCompleted: firestoreData['onboardingCompleted'],
      createdAt: firestoreData['createdAt'],
      updatedAt: firestoreData['updatedAt'],
      photoUrl: firestoreData['photoUrl'],
      orgId: firestoreData['orgId'],
      roles: firestoreData['roles'],
      onboardingCompletedAt: firestoreData['onboardingCompletedAt'],
      homeConfig: firestoreData['homeConfig'],
      preferences: firestoreData['preferences'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'displayName': displayName,
      'email': email,
      'onboardingCompleted': onboardingCompleted,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'photoUrl': photoUrl,
      'orgId': orgId,
      'roles': roles,
      'onboardingCompletedAt': onboardingCompletedAt,
      'homeConfig': homeConfig,
      'preferences': preferences,
    };
  }
}
