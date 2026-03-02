import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:vivordo_health/screens/goals_screen.dart';

class GoalModel {
  final String userId;
  String title;
  String? description;
  String? category;
  String? targetMetricType;
  double? targetValue;
  String? targetUnit;
  String? direction;
  FieldValue? startDate;
  FieldValue? endDate;
  String status;
  Map<String, dynamic>? progress;
  final FieldValue createdAt;
  FieldValue updatedAt;

  GoalModel({
    required this.userId,
    required this.title,
    required this.status,
    required this.progress,
    required this.createdAt,
    required this.updatedAt,
    this.description,
    this.category,
    this.targetMetricType,
    this.targetValue,
    this.targetUnit,
    this.direction,
    this.startDate,
    this.endDate,
  });

  Map<String, dynamic> toMap() {
    return {
      "userId": userId,
      "title": title,
      "description": description,
      "category": category,
      "targetMetricType": targetMetricType,
      "targetValue": targetValue,
      "targetUnit": targetUnit,
      "direction": direction,
      "startDate": startDate,
      "endDate": endDate,
      "status": status,
      "progress": progress,
      "createdAt": createdAt,
      "updatedAt": updatedAt,
    };
  }

  factory GoalModel.fromMap(Map<String, dynamic> map) {
    return GoalModel(
      userId: map["userId"] ?? "",
      title: map["title"] ?? "",
      status: map["status"] ?? "",
      progress: map["progress"] != null
          ? Map<String, dynamic>.from(map["progress"])
          : {},

      createdAt: map["createdAt"],
      updatedAt: map["updatedAt"],

      description: map["description"],
      category: map["category"],
      targetMetricType: map["targetMetricType"],
      targetValue: map["targetValue"],
      targetUnit: map["targetUnit"],
      direction: map["direction"],
      startDate: map["startDate"],
      endDate: map["endDate"],
    );
  }

  Future<void> toFirestore() async {
    await FirebaseFirestore.instance.collection('goals').add(toMap());
  }

  Goal toGoal({required String id}) {
    return Goal(
      id: id,
      title: title,
      subtext: "Daily", //TODO: Figure out storage of subtext in GoalModel
      color: Color(0xFF7B6EF6),
      days: {},
    );
  }
}
