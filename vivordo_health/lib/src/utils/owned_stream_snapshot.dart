import 'dart:async';
import 'package:flutter/widgets.dart';

/// Owns one subscription independently of lazily mounted UI listeners.
/// Keeps the latest snapshot while a list section is offscreen.
class OwnedStreamSnapshot<T> extends ValueNotifier<AsyncSnapshot<T>> {
  OwnedStreamSnapshot() : super(AsyncSnapshot<T>.nothing());

  StreamSubscription<T>? _subscription;
  int _generation = 0;

  void connect(Stream<T> stream) {
    final generation = ++_generation;
    unawaited(_subscription?.cancel());
    value = AsyncSnapshot<T>.waiting();
    _subscription = stream.listen(
      (data) {
        if (generation == _generation) {
          value = AsyncSnapshot.withData(ConnectionState.active, data);
        }
      },
      onError: (Object error, StackTrace stack) {
        if (generation == _generation) {
          value = AsyncSnapshot.withError(ConnectionState.active, error, stack);
        }
      },
      onDone: () {
        if (generation == _generation) {
          value = value.inState(ConnectionState.done);
        }
      },
    );
  }

  @override
  void dispose() {
    ++_generation;
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
