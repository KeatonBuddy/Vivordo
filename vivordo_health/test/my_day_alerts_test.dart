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

  test('the brief only says room to spare when no alert is showing', () {
    expect(roomToSpareHeadline(), 'Room to spare today');
    expect(goEasy(), isFalse);
    expect(goEasy(trainingLoad: 'high'), isTrue);
    expect(
      roomToSpareHeadline(burnout: 'steady', trainingLoad: 'building'),
      'Room to spare today',
    );
    expect(roomToSpareHeadline(burnout: 'watch'), 'Room today, but go easy');
    expect(
      roomToSpareHeadline(trainingLoad: 'strained'),
      'Room today, but go easy',
    );
  });
}
