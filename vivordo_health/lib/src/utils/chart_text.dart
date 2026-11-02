import 'package:flutter/widgets.dart';

/// Chart labels follow the system text size, capped so they still fit
/// between ticks. Painters have no BuildContext, so this reads the setting
/// from the platform; a change shows on the chart's next repaint.
TextScaler get chartTextScaler => TextScaler.linear(
  WidgetsBinding.instance.platformDispatcher.textScaleFactor.clamp(1.0, 1.35),
);
