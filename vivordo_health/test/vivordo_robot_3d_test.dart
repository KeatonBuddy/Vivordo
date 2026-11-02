import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/widgets/vivordo_robot.dart';

void main() {
  String shown(WidgetTester tester) =>
      ((tester.widget<Image>(find.byType(Image)).image) as AssetImage)
          .assetName;

  Widget robot({int waves = 0, int cheers = 0}) => MaterialApp(
    home: VivordoRobot3D(waves: waves, cheers: cheers),
  );

  testWidgets('a cheer plays the arms-up frames, a wave the wave frames', (
    tester,
  ) async {
    await tester.pumpWidget(robot());
    expect(shown(tester), 'assets/robot_wave/00.png');

    await tester.pumpWidget(robot(cheers: 1));
    await tester.pump(const Duration(milliseconds: 300));
    expect(shown(tester), startsWith('assets/robot_cheer/'));
    await tester.pumpAndSettle();
    expect(shown(tester), endsWith('/00.png'), reason: 'stands after');

    await tester.pumpWidget(robot(cheers: 1, waves: 1));
    await tester.pump(const Duration(milliseconds: 300));
    expect(shown(tester), startsWith('assets/robot_wave/'));
    expect(shown(tester), isNot('assets/robot_wave/00.png'));
    await tester.pumpAndSettle();
  });
}
