import 'package:flutter/material.dart';

/// Tracks the mounted workout across root and nested navigators.
class ActiveWorkoutNavigation {
  static List<Route<dynamic>> _routes = [];

  static void register(BuildContext context) {
    final routes = <Route<dynamic>>[];
    Route<dynamic>? route = ModalRoute.of(context);
    while (route != null && !routes.contains(route)) {
      routes.add(route);
      final navigator = route.navigator;
      route = navigator == null ? null : ModalRoute.of(navigator.context);
    }
    _routes = routes;
  }

  static void unregister(Route<dynamic>? route) {
    if (_routes.isNotEmpty && identical(_routes.first, route)) _routes = [];
  }

  static bool focusExisting() {
    if (_routes.isEmpty || _routes.any((route) => !route.isActive)) {
      return false;
    }
    // Reveal the containing main-app route before focusing its inner route.
    for (final route in _routes.reversed) {
      route.navigator!.popUntil((candidate) => identical(candidate, route));
    }
    return true;
  }
}
