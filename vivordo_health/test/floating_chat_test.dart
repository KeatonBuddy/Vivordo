import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/widgets/floating_chat.dart';

void main() {
  // The Duo's inner display in the iOS 27.2 simulator, with the tab rail.
  const bounds = FloatingBoxBounds(screen: Size(951, 669), rail: 88);
  const hinge = 951 / 2;

  test('a box let go across the hinge settles on the nearer half', () {
    final left = bounds.settle(const Rect.fromLTWH(200, 100, 340, 440));
    expect(left.right, lessThanOrEqualTo(hinge - 12));
    final right = bounds.settle(const Rect.fromLTWH(400, 100, 340, 440));
    expect(right.left, greaterThanOrEqualTo(hinge + 12));
    expect(right.right, lessThanOrEqualTo(951 - 88 - 8));
  });

  test('a wide box shrinks to fit the narrower right half', () {
    final box = bounds.settle(const Rect.fromLTWH(480, 100, 440, 440));
    expect(box.left, greaterThanOrEqualTo(hinge + 12));
    expect(box.right, lessThanOrEqualTo(951 - 88 - 8));
    expect(box.width, lessThan(440));
  });

  test('resizing stops at the hinge, the rail and the minimum size', () {
    const box = Rect.fromLTWH(64, 120, 340, 440);
    expect(bounds.resize(box, const Offset(900, 900)).right, hinge - 12);
    expect(bounds.resize(box, const Offset(900, 900)).bottom, 669 - 8);
    expect(
      bounds.resize(box, const Offset(-900, -900)).size,
      FloatingBoxBounds.minSize,
    );
  });

  test('the box opens out of the robot button and ends as itself', () {
    const box = Rect.fromLTWH(64, 120, 340, 440);
    const robot = Offset(893, 482);
    final start = chatMorph(t: 0, box: box, origin: robot);
    // A circle the button's size, centred on the button.
    expect(box.center + start.offset, robot);
    expect(start.scaleX * box.width, closeTo(62, .001));
    expect(start.scaleY * box.height, closeTo(62, .001));
    expect(start.radius, 31);
    final end = chatMorph(t: 1, box: box, origin: robot);
    expect(end.offset, Offset.zero);
    expect(end.scaleX, 1);
    expect(end.scaleY, 1);
    expect(end.radius, 26);
    // Part way, it has reached further across than it has filled out.
    final mid = chatMorph(t: .4, box: box, origin: robot);
    expect(mid.scaleX, greaterThan(mid.scaleY));
    // A spring that overshoots never grows it past full size.
    expect(chatMorph(t: 1.2, box: box, origin: robot).scaleX, 1);
  });

  test('the box stays above the keyboard', () {
    const typing = FloatingBoxBounds(
      screen: Size(951, 669),
      rail: 88,
      bottom: 300,
    );
    final box = typing.settle(const Rect.fromLTWH(64, 200, 340, 440));
    expect(box.bottom, lessThanOrEqualTo(669 - 300 - 8));
    expect(box.top, greaterThanOrEqualTo(8));
  });
}
