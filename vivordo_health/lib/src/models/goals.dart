import 'package:cloud_firestore/cloud_firestore.dart';

class Goals {
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

  Goals({
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

  factory Goals.fromMap(Map<String, dynamic> map) {
    return Goals(
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
}
