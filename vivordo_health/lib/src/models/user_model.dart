import 'dart:core';

import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String? displayName;
  final String? email;
  final String? photoUrl;
  final String? orgId;
  final List<String>? roles;
  final bool onboardingCompleted;
  final Timestamp? onboardingCompletedAt;
  final Map<String, dynamic>? preferences; //should we create models for these?
  final Map<String, dynamic>? homeConfig; //create model?
  final Timestamp? createdAt;
  final Timestamp? updatedAt;

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

  factory UserModel.fromJson(Map<String, dynamic> firestoreData, String id) {
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

  Map<String, dynamic> toJson() {
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
