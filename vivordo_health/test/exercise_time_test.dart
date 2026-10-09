import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/services/workout_service.dart';

void main() {
  test('adds app minutes on top of health minutes', () {
    final result = exerciseTimeWithAppMinutes({
      'healthSum': 20,
      'workoutMinutes': 10,
      'sum': 30,
    }, 45);
    expect(result['healthSum'], 20);
    expect(result['workoutMinutes'], 55);
    expect(result['sum'], 75);
  });

  test('starts an empty day from zero', () {
    final result = exerciseTimeWithAppMinutes(null, 30);
    expect(result['workoutMinutes'], 30);
    expect(result['sum'], 30);
    expect(result['unit'], 'min');
  });

  test('treats a legacy sum without healthSum as health minutes', () {
    final result = exerciseTimeWithAppMinutes({'sum': 25}, 15);
    expect(result['healthSum'], 25);
    expect(result['sum'], 40);
  });

  test('removing minutes never goes below zero', () {
    final result = exerciseTimeWithAppMinutes({
      'healthSum': 5,
      'workoutMinutes': 10,
      'sum': 15,
    }, -30);
    expect(result['workoutMinutes'], 0);
    expect(result['sum'], 5);
  });
}
