import 'dart:async';

/// Shares one upstream listener and replays its most recent value to each
/// new subscriber. Create a separate instance for each account.
Stream<T> replayLatest<T>(Stream<T> source) {
  T? latest;
  var hasValue = false;
  final shared = source.map((value) {
    latest = value;
    hasValue = true;
    return value;
  }).asBroadcastStream();
  return Stream<T>.multi((controller) {
    final subscription = shared.listen(
      controller.addSync,
      onError: controller.addErrorSync,
      onDone: controller.closeSync,
    );
    if (hasValue) controller.addSync(latest as T);
    controller.onCancel = subscription.cancel;
    controller.onPause = subscription.pause;
    controller.onResume = subscription.resume;
  }, isBroadcast: true);
}
