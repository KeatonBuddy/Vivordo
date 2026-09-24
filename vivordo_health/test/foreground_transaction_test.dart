import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/foreground_transaction.dart';

void main() {
  testWidgets('only resumed apps can start transaction work', (tester) async {
    for (final state in AppLifecycleState.values) {
      tester.binding.handleAppLifecycleStateChanged(state);
      expect(canRunForegroundTransaction, state == AppLifecycleState.resumed);
      if (state == AppLifecycleState.resumed) {
        expect(requireForegroundTransaction, returnsNormally);
      } else {
        expect(requireForegroundTransaction, throwsStateError);
      }
    }
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
}
