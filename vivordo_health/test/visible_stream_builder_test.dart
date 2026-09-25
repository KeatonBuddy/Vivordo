import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/widgets/visible_stream_builder.dart';
import 'package:vivordo_health/src/utils/owned_stream_snapshot.dart';

void main() {
  testWidgets(
    'hidden UI disconnects, retains data and resumes without backlog',
    (tester) async {
      final stream = StreamController<int>.broadcast();
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
      final hiddenBuilds = builds;
      expect(stream.hasListener, isFalse);
      stream.add(2);
      await tester.pump();
      expect(builds, hiddenBuilds);
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

  test(
    'owned snapshot retains data across suspension and reconnects',
    () async {
      final stream = StreamController<int>.broadcast();
      final snapshot = OwnedStreamSnapshot<int>();
      snapshot.connect(stream.stream);
      stream.add(1);
      await Future<void>.delayed(Duration.zero);
      snapshot.setActive(false);
      expect(stream.hasListener, isFalse);
      stream.add(2);
      await Future<void>.delayed(Duration.zero);
      expect(snapshot.value.data, 1);
      snapshot.setActive(true);
      stream.add(3);
      await Future<void>.delayed(Duration.zero);
      expect(snapshot.value.data, 3);
      snapshot.dispose();
      await stream.close();
    },
  );
}
