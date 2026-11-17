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
