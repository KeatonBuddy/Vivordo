import 'package:cloud_firestore/cloud_firestore.dart';

class Insights {
  final String userId;
  String? source;
  String? title;
  String? body;
  String? severity;
  String? category;
  List<String>? relatedMetrics;
  List<String>? relatedMetricsPeriods;
  List<String>? relatedQuestionnareIds;
  String? goalId;
  bool? acknowledged;
  Timestamp? acknowledgedAt;
  Timestamp createdAt;
  Timestamp updatedAt;

  Insights({
    required this.userId,
    required this.createdAt,
    required this.updatedAt,

    this.source,
    this.title,
    this.body,
    this.severity,
    this.category,

    this.relatedMetrics,
    this.relatedMetricsPeriods,
    this.relatedQuestionnareIds,

    this.goalId,
    this.acknowledged,
    this.acknowledgedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      "userId": userId,
      "source": source,
      "title": title,
      "body": body,
      "severity": severity,
      "category": category,
      "relatedMetrics": relatedMetrics,
      "relatedMetricsPeriods": relatedMetricsPeriods,
      "relatedQuestionnareIds": relatedQuestionnareIds,
      "goalId": goalId,
      "acknowledged": acknowledged,
      "acknowledgedAt": acknowledgedAt,
      "createdAt": createdAt,
      "updatedAt": updatedAt,
    };
  }

  factory Insights.fromMap(Map<String, dynamic> map) {
    return Insights(
      userId: map["userId"] ?? "",
      source: map["source"],
      title: map["title"],
      body: map["body"],
      severity: map["severity"],
      category: map["category"],

      relatedMetrics: map["relatedMetrics"] != null
          ? List<String>.from(map["relatedMetrics"])
          : null,

      relatedMetricsPeriods: map["relatedMetricsPeriods"] != null
          ? List<String>.from(map["relatedMetricsPeriods"])
          : null,

      relatedQuestionnareIds: map["relatedQuestionnareIds"] != null
          ? List<String>.from(map["relatedQuestionnareIds"])
          : null,

      goalId: map["goalId"],
      acknowledged: map["acknowledged"],
      acknowledgedAt: map["acknowledgedAt"] as Timestamp?,

      createdAt: map["createdAt"] as Timestamp,
      updatedAt: map["updatedAt"] as Timestamp,
    );
  }

  Future<void> toFirestore() async {
    await FirebaseFirestore.instance.collection('insights').add(toMap());
  }
}
