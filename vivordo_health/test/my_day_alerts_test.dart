import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/my_day_alerts.dart';

void main() {
  test('the most serious alert comes first', () {
    expect(
      rankMyDayAlerts(
        burnout: 'watch',
        trainingLoad: 'strained',
        weeklyReview: true,
      ),
      [MyDayAlert.trainingLoad, MyDayAlert.burnout, MyDayAlert.weeklyReview],
    );
    expect(rankMyDayAlerts(burnout: 'warning', trainingLoad: 'strained'), [
      MyDayAlert.burnout,
      MyDayAlert.trainingLoad,
    ]);
    expect(rankMyDayAlerts(burnout: 'watch', trainingLoad: 'high'), [
      MyDayAlert.burnout,
      MyDayAlert.trainingLoad,
    ]);
  });

  test('calm days show nothing', () {
    expect(
      rankMyDayAlerts(burnout: 'steady', trainingLoad: 'building'),
      isEmpty,
    );
    expect(rankMyDayAlerts(), isEmpty);
  });
}
