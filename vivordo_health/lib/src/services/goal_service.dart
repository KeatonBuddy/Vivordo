import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:vivordo_health/src/models/goals.dart';

class GoalService {
  //create goal
  //TODO: update goal - with 1 get goal defoposit
  //TODO: get goal - get with 1 autoid
  //TODO: get all goals - query for all

  static Future<void> createGoal({
    required String userId,
    required String title,
    required String status,
    String? description,
    String? category,
    String? targetMetricType,
    double? targetValue,
    String? targetUnit,
    String? direction,
    FieldValue? endDate,
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
      userId: userId,
      title: title,
      description: description,
      category: category,
      targetMetricType: targetMetricType,
      targetValue: targetValue,
      targetUnit: targetUnit,
      direction: direction,
      startDate: FieldValue.serverTimestamp(),
      endDate: endDate,
      status: status,
      progress: progress,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    );

    await FirebaseFirestore.instance.collection('goals').add(newGoal.toMap());
  }
}
