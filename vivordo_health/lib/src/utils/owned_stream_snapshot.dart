import 'dart:async';
import 'package:flutter/widgets.dart';

/// How long a hidden tab keeps its live listeners. Reconnecting makes
/// Firestore re-send every document the listener covers, encoded on the iOS
/// main thread, which made each bottom-bar switch stall. A tab hidden longer
/// than this still frees its listeners.
const kHiddenStreamGrace = Duration(seconds: 30);

/// Owns one subscription independently of lazily mounted UI listeners.
/// Keeps the latest snapshot while a list section is offscreen.
class OwnedStreamSnapshot<T> extends ValueNotifier<AsyncSnapshot<T>> {
  OwnedStreamSnapshot() : super(AsyncSnapshot<T>.nothing());

  StreamSubscription<T>? _subscription;
  int _generation = 0;
  Stream<T> Function()? _streamFactory;
  bool _active = true;
  Timer? _disconnect;
  AsyncSnapshot<T>? _pending;

  /// Hiding keeps the subscription for [kHiddenStreamGrace], holding updates
  /// back so hidden UI does not rebuild; showing again publishes the latest.
  void setActive(bool active) {
    if (_active == active) return;
    _active = active;
    _disconnect?.cancel();
    if (!active) {
      _disconnect = Timer(kHiddenStreamGrace, () {
        ++_generation;
        unawaited(_subscription?.cancel());
        _subscription = null;
      });
      return;
    }
    final pending = _pending;
    _pending = null;
    if (pending != null) value = pending;
    if (_subscription == null && _streamFactory != null) {
      _listen(_streamFactory!());
    }
  }

  void _publish(AsyncSnapshot<T> next) {
    if (_active) {
      value = next;
    } else {
      _pending = next;
    }
  }

  /// Use only with streams that support listening again after cancellation.
  void connect(Stream<T> stream) {
    connectFactory(() => stream);
  }

  /// Creates a fresh stream each time the owner becomes active. Required for
  /// single-subscription controllers such as DailyPriorityService.watch().
  void connectFactory(Stream<T> Function() createStream) {
    _streamFactory = createStream;
    _pending = null;
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
          _publish(AsyncSnapshot.withData(ConnectionState.active, data));
        }
      },
      onError: (Object error, StackTrace stack) {
        if (generation == _generation) {
          _publish(
            AsyncSnapshot.withError(ConnectionState.active, error, stack),
          );
        }
      },
      onDone: () {
        if (generation == _generation) {
          _publish((_pending ?? value).inState(ConnectionState.done));
        }
      },
    );
  }

  @override
  void dispose() {
    _disconnect?.cancel();
    ++_generation;
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
