import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// iOS Reduce Transparency, which Flutter doesn't expose (AppDelegate reports
/// it and its changes). Glass surfaces go solid while it's on.
class ReduceTransparency {
  ReduceTransparency._();

  static const _channel = MethodChannel('com.vivordo.health/accessibility');
  static final enabled = ValueNotifier<bool>(false);
  static bool _started = false;

  static void start() {
    if (_started) return;
    _started = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'reduceTransparency') {
        enabled.value = call.arguments == true;
      }
    });
    _channel
        .invokeMethod<bool>('reduceTransparency')
        .then((on) => enabled.value = on ?? false, onError: (_) {});
  }
}
