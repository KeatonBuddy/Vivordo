import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/owned_stream_snapshot.dart';

void main() {
  testWidgets('section can unmount and remount without resubscribing', (
    tester,
  ) async {
    var listens = 0;
    var cancellations = 0;
    final source = StreamController<int>(
      onListen: () => listens++,
      onCancel: () => cancellations++,
    );
    final owner = OwnedStreamSnapshot<int>()..connect(source.stream);
    Widget section() => Directionality(
      textDirection: TextDirection.ltr,
      child: ValueListenableBuilder<AsyncSnapshot<int>>(
        valueListenable: owner,
        builder: (_, snapshot, _) => Text('${snapshot.data}'),
      ),
    );
    await tester.pumpWidget(section());
    source.add(1);
    await tester.pump();
    await tester.pump();
    expect(find.text('1'), findsOneWidget);
    // Equivalent to a ListView disposing an offscreen section.
    await tester.pumpWidget(const SizedBox());
    source.add(2);
    await tester.pump();
    await tester.pumpWidget(section());
    expect(find.text('2'), findsOneWidget);
    expect(listens, 1);
    expect(cancellations, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    owner.dispose();
    await tester.pump();
    expect(cancellations, 1);
    unawaited(source.close());
    await tester.pump();
  });

  test(
    'rollover cancels old source, resets snapshot and accepts new updates',
    () async {
      var cancelled = false;
      final old = StreamController<int>(onCancel: () => cancelled = true);
      final next = StreamController<int>();
      final owner = OwnedStreamSnapshot<int>()..connect(old.stream);
      old.add(1);
      await Future<void>.delayed(Duration.zero);
      expect(owner.value.data, 1);
      owner.connect(next.stream);
      expect(cancelled, isTrue);
      expect(owner.value.connectionState, ConnectionState.waiting);
      expect(owner.value.hasData, isFalse);
      old.add(99);
      next.addError(StateError('offline'));
      await Future<void>.delayed(Duration.zero);
      expect(owner.value.hasError, isTrue);
      next.add(2);
      await Future<void>.delayed(Duration.zero);
      expect(owner.value.data, 2);
      expect(owner.value.hasError, isFalse);
      owner.dispose();
      await old.close();
      await next.close();
    },
  );
}
