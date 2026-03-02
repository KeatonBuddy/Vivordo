import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:vivordo_health/screens/goals_screen.dart';
import 'package:vivordo_health/src/models/goal_model.dart';

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

    GoalModel newGoal = GoalModel(
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

    await newGoal.toFirestore();
  }

  static Future<List<Goal>> getGoals({required String userId}) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('goals')
        .where('userId', isEqualTo: userId)
        .get();

    List<Goal> myGoals = [];
    for (var doc in snapshot.docs) {
      GoalModel curr = GoalModel.fromMap(doc.data());
      myGoals.add(curr.toGoal(id: doc.id));
    }

    return myGoals;
  }
}
