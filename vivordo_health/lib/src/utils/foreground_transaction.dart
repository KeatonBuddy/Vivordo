import 'package:flutter/widgets.dart';

bool get canRunForegroundTransaction =>
    WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

void requireForegroundTransaction() {
  if (!canRunForegroundTransaction) {
    throw StateError('Transaction deferred until the app is foregrounded');
  }
}
