import 'package:flutter/material.dart';

import '../theme/vivordo_theme.dart';

/// The launch logo on the page colour. Every wait between tapping the icon
/// and the first screen shows this, so launch reads as one continuous
/// moment instead of a run of spinners.
class LaunchSplash extends StatelessWidget {
  const LaunchSplash({super.key});

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.vivordoColors.page,
    child: Center(
      child: Image.asset(
        'assets/vivordo_splash_logo_full.png',
        width: 220,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      ),
    ),
  );
}
