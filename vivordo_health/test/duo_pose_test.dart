import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/widgets/duo_layout.dart';

void main() {
  test('iPhone Duo poses from the window size', () {
    expect(DuoPose.fromSize(const Size(402, 874)), DuoPose.none); // 18 Pro
    expect(DuoPose.fromSize(const Size(393, 852)), DuoPose.none);
    expect(DuoPose.fromSize(const Size(466, 678)), DuoPose.closed);
    // The iOS 27.2 simulator's inner display is 951×669 pt.
    expect(DuoPose.fromSize(const Size(951, 669)), DuoPose.openLandscape);
    expect(DuoPose.fromSize(const Size(669, 951)), DuoPose.openPortrait);
    expect(DuoPose.fromSize(const Size(890, 626)), DuoPose.openLandscape);
  });

  testWidgets('DuoPanes puts the gutter on the hinge', (tester) async {
    tester.view.physicalSize = const Size(890, 626);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Padding(
          padding: EdgeInsets.only(left: 20, right: 111),
          child: DuoPanes(
            leftInset: 20,
            extra: SizedBox(key: Key('left'), height: 10),
            cover: SizedBox(key: Key('right'), height: 10),
          ),
        ),
      ),
    );
    // Left pane ends 16 before the hinge at 445, right starts 16 after.
    expect(tester.getRect(find.byKey(const Key('left'))).right, 445 - 16);
    expect(tester.getRect(find.byKey(const Key('right'))).left, 445 + 16);
  });

  test('tab bar edge and pane count per pose', () {
    expect(DuoPose.none.trailingTabBar, isFalse);
    expect(DuoPose.closed.trailingTabBar, isTrue);
    expect(DuoPose.openLandscape.trailingTabBar, isTrue);
    expect(DuoPose.openPortrait.trailingTabBar, isFalse);
    expect(DuoPose.openLandscape.twoPane, isTrue);
    expect(DuoPose.closed.twoPane, isFalse);
  });
}
