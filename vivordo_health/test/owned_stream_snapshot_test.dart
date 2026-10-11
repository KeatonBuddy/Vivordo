import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/owned_stream_snapshot.dart';

void main() {
  testWidgets(
    'single-use priority streams keep live data across a quick hide and '
    'reconnect after the grace',
    (tester) async {
      var latestPriorities = ['First priority'];
      final sources = <StreamController<List<String>>>[];
      var cancellations = 0;
      Stream<List<String>> createStream() {
        late StreamController<List<String>> source;
        source = StreamController<List<String>>(
          onListen: () => source.add(List.of(latestPriorities)),
          onCancel: () => cancellations++,
        );
        sources.add(source);
        return source.stream;
      }

      final owner = OwnedStreamSnapshot<List<String>>()
        ..connectFactory(createStream);
      await tester.pump();
      expect(owner.value.data, ['First priority']);

      // Opening a modal or flipping tabs: the live stream keeps delivering,
      // held back until shown, and no new listener is built.
      owner.setActive(false);
      sources.last.add(['Edited while hidden']);
      await tester.pump();
      expect(owner.value.data, ['First priority']);
      owner.setActive(true);
      expect(owner.value.data, ['Edited while hidden']);
      expect(sources.length, 1);
      expect(cancellations, 0);

      // Hidden past the grace: released, and showing builds a fresh listener.
      for (var index = 0; index < 3; index++) {
        final cached = owner.value.data;
        owner.setActive(false);
        await tester.pump(kHiddenStreamGrace);
        expect(cancellations, index + 1);
        latestPriorities = ['Edited while hidden $index'];
        expect(sources.length, index + 1);
        owner.setActive(true);
        expect(owner.value.data, cached);
        await tester.pump();
        expect(sources.length, index + 2);
        expect(owner.value.data, latestPriorities);
        expect(owner.value.hasError, false);
      }
      owner.dispose();
      expect(cancellations, sources.length);
      for (final source in sources) {
        unawaited(source.close());
      }
    },
  );

  test(
    'inactive startup and hidden day rollover use only the latest factory',
    () async {
      var oldListens = 0;
      var newListens = 0;
      final owner = OwnedStreamSnapshot<int>()..setActive(false);
      owner.connectFactory(() {
        oldListens++;
        return Stream.value(1);
      });
      expect(oldListens, 0);
      owner.connectFactory(() {
        newListens++;
        return Stream.value(2);
      });
      expect(newListens, 0);
      owner.setActive(true);
      await Future<void>.delayed(Duration.zero);
      expect(oldListens, 0);
      expect(newListens, 1);
      expect(owner.value.data, 2);
      owner.dispose();
    },
  );

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
