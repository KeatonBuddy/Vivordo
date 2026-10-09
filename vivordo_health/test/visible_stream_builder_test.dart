import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/widgets/visible_stream_builder.dart';
import 'package:vivordo_health/src/utils/owned_stream_snapshot.dart';

void main() {
  testWidgets(
    'hidden UI disconnects after the grace, retains data, resumes without backlog',
    (tester) async {
      var listens = 0;
      final stream = StreamController<int>.broadcast(onListen: () => listens++);
      var builds = 0;
      Widget page(bool active) => Directionality(
        textDirection: TextDirection.ltr,
        child: TickerMode(
          enabled: active,
          child: VisibleStreamBuilder<int>(
            stream: stream.stream,
            builder: (_, snapshot) {
              builds++;
              return Text('${snapshot.data}');
            },
          ),
        ),
      );
      await tester.pumpWidget(page(true));
      stream.add(1);
      await tester.pump();
      await tester.pump();
      await tester.pumpWidget(page(false));
      // A quick switch back reuses the live listener.
      await tester.pump(kHiddenStreamGrace ~/ 2);
      expect(stream.hasListener, isTrue);
      await tester.pumpWidget(page(true));
      await tester.pumpWidget(page(false));
      await tester.pump(kHiddenStreamGrace ~/ 2);
      expect(listens, 1);
      expect(stream.hasListener, isTrue);
      await tester.pump(kHiddenStreamGrace);
      expect(stream.hasListener, isFalse);
      final disconnectedBuilds = builds;
      stream.add(2);
      await tester.pump();
      expect(builds, disconnectedBuilds);
      expect(find.text('1'), findsOneWidget);
      await tester.pumpWidget(page(true));
      expect(stream.hasListener, isTrue);
      expect(find.text('1'), findsOneWidget);
      stream.add(3);
      await tester.pump();
      await tester.pump();
      expect(find.text('3'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await stream.close();
    },
  );

  testWidgets(
    'owned snapshot holds hidden updates, then disconnects after the grace',
    (tester) async {
      var listens = 0;
      final stream = StreamController<int>.broadcast(onListen: () => listens++);
      final snapshot = OwnedStreamSnapshot<int>();
      var notifications = 0;
      snapshot.addListener(() => notifications++);
      snapshot.connect(stream.stream);
      stream.add(1);
      await tester.pump();
      snapshot.setActive(false);
      stream.add(2);
      await tester.pump();
      final hidden = notifications;
      expect(snapshot.value.data, 1, reason: 'hidden UI does not rebuild');
      snapshot.setActive(true);
      expect(snapshot.value.data, 2, reason: 'latest is published on return');
      expect(listens, 1);
      expect(notifications, hidden + 1);
      snapshot.setActive(false);
      await tester.pump(kHiddenStreamGrace);
      expect(stream.hasListener, isFalse);
      stream.add(4);
      await tester.pump();
      expect(snapshot.value.data, 2);
      snapshot.setActive(true);
      stream.add(3);
      await tester.pump();
      expect(snapshot.value.data, 3);
      snapshot.dispose();
      await stream.close();
    },
  );
}
