import 'dart:async';
import 'package:flutter/widgets.dart';

/// Owns one subscription independently of lazily mounted UI listeners.
/// Keeps the latest snapshot while a list section is offscreen.
class OwnedStreamSnapshot<T> extends ValueNotifier<AsyncSnapshot<T>> {
  OwnedStreamSnapshot() : super(AsyncSnapshot<T>.nothing());

  StreamSubscription<T>? _subscription;
  int _generation = 0;
  Stream<T> Function()? _streamFactory;
  bool _active = true;

  void setActive(bool active) {
    if (_active == active) return;
    _active = active;
    ++_generation;
    unawaited(_subscription?.cancel());
    _subscription = null;
    if (active && _streamFactory != null) _listen(_streamFactory!());
  }

  /// Use only with streams that support listening again after cancellation.
  void connect(Stream<T> stream) {
    connectFactory(() => stream);
  }

  /// Creates a fresh stream each time the owner becomes active. Required for
  /// single-subscription controllers such as DailyPriorityService.watch().
  void connectFactory(Stream<T> Function() createStream) {
    _streamFactory = createStream;
    ++_generation;
    unawaited(_subscription?.cancel());
    _subscription = null;
    value = AsyncSnapshot<T>.waiting();
    if (_active) _listen(createStream());
  }

  void _listen(Stream<T> stream) {
    final generation = ++_generation;
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
