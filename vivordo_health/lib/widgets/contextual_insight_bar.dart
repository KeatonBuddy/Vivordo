import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/vivordo_theme.dart';
import 'vivordo_robot.dart';

@immutable
class ScreenInsight {
  const ScreenInsight(this.screen, this.title, this.message);
  final String screen;
  final String title;
  final String message;
  String get prompt =>
      'Help me understand and act on this $title insight from Vivordo: "$message". Use available data, acknowledge missing information, and do not assume this proves a medical cause.';
}

/// Screen-owned summaries only: this controller never fetches health data or AI.
class ScreenInsightController extends ChangeNotifier {
  final Map<Object, (Route<dynamic>?, ScreenInsight)> _sources = {};
  Route<dynamic>? route;
  String screen = 'home';
  bool _disposed = false;

  ScreenInsight? get current {
    for (final entry in _sources.values.toList().reversed) {
      if (entry.$1 == route &&
          (route?.settings.name != 'main-tabs' || entry.$2.screen == screen)) {
        return entry.$2;
      }
    }
    return null;
  }

  void select(Route<dynamic>? value, String tab) {
    if (_disposed) return;
    route = value;
    screen = tab;
    notifyListeners();
  }

  void publish(Object owner, Route<dynamic>? route, ScreenInsight insight) {
    if (_disposed) return;
    final old = _sources[owner];
    if (old?.$1 == route &&
        old?.$2.screen == insight.screen &&
        old?.$2.message == insight.message) {
      return;
    }
    _sources[owner] = (route, insight);
    notifyListeners();
  }

  void remove(Object owner) {
    if (!_disposed && _sources.remove(owner) != null) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sources.clear();
    super.dispose();
  }
}

class ScreenInsightScope extends InheritedWidget {
  const ScreenInsightScope({
    super.key,
    required this.controller,
    required super.child,
  });
  final ScreenInsightController controller;
  @override
  bool updateShouldNotify(ScreenInsightScope oldWidget) =>
      controller != oldWidget.controller;
}

extension ContextualInsightWidget on Widget {
  Widget withScreenInsight(ScreenInsight insight) =>
      _InsightSource(insight: insight, child: this);
}

class _InsightSource extends StatefulWidget {
  const _InsightSource({required this.insight, required this.child});
  final ScreenInsight insight;
  final Widget child;
  @override
  State<_InsightSource> createState() => _InsightSourceState();
}

class _InsightSourceState extends State<_InsightSource> {
  ScreenInsightController? _controller;
  void _publish() {
    final controller = context
        .dependOnInheritedWidgetOfExactType<ScreenInsightScope>()
        ?.controller;
    _controller = controller;
    final route = ModalRoute.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) controller?.publish(this, route, widget.insight);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _publish();
  }

  @override
  void didUpdateWidget(covariant _InsightSource oldWidget) {
    super.didUpdateWidget(oldWidget);
    _publish();
  }

  @override
  void dispose() {
    final controller = _controller;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => controller?.remove(this),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class ContextualInsightBar extends StatefulWidget {
  const ContextualInsightBar({
    super.key,
    required this.insight,
    required this.collapsed,
    required this.onAsk,
    this.suppressed = false,
  });
  final ScreenInsight? insight;
  final Widget collapsed;
  final ValueChanged<String> onAsk;
  final bool suppressed;
  @override
  State<ContextualInsightBar> createState() => _ContextualInsightBarState();
}

class _ContextualInsightBarState extends State<ContextualInsightBar> {
  bool _dismissed = false;
  Timer? _delay;
  bool _ready = false;
  bool _expanded = false;
  @override
  void initState() {
    super.initState();
    _schedule();
  }

  void _schedule() {
    _delay?.cancel();
    _ready = false;
    _expanded = false;
    if (widget.insight == null || widget.suppressed) return;
    _delay = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  void didUpdateWidget(covariant ContextualInsightBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.insight?.screen != widget.insight?.screen) {
      _dismissed = false;
    }
    if (oldWidget.insight?.screen != widget.insight?.screen ||
        oldWidget.suppressed != widget.suppressed) {
      _schedule();
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final insight = widget.insight;
    if (!_ready || insight == null || widget.suppressed || _dismissed) {
      return _animate(
        Align(
          key: const ValueKey('button'),
          alignment: Alignment.centerRight,
          child: widget.collapsed,
        ),
      );
    }
    final colors = context.vivordoColors;
    return _animate(
      RepaintBoundary(
        key: ValueKey(insight.screen),
        child: Material(
          color: colors.card,
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
            side: const BorderSide(color: VivordoTheme.brand),
          ),
          clipBehavior: Clip.antiAlias,
          child: AnimatedSize(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 180),
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .45,
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const CircleAvatar(
                            backgroundColor: VivordoTheme.brand,
                            child: VivordoRobot(size: 26, faceOnly: true),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: InkWell(
                              onTap: () =>
                                  setState(() => _expanded = !_expanded),
                              child: Text(
                                _expanded ? insight.title : insight.message,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colors.textPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: _expanded
                                ? 'Collapse insight'
                                : 'Expand insight',
                            onPressed: () =>
                                setState(() => _expanded = !_expanded),
                            icon: Icon(
                              _expanded ? Icons.expand_more : Icons.expand_less,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Dismiss insights for this screen',
                            onPressed: () => setState(() => _dismissed = true),
                            icon: const Icon(Icons.close, size: 20),
                          ),
                        ],
                      ),
                      if (_expanded) ...[
                        const SizedBox(height: 12),
                        Text(
                          insight.message,
                          style: TextStyle(color: colors.textPrimary),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Based on the data shown on this screen. Wellness guidance, not medical advice.',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: () => widget.onAsk(insight.prompt),
                          icon: const Icon(Icons.chat_bubble_outline),
                          label: const Text('Ask Vivordo AI'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _animate(Widget child) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 280);
    return AnimatedSize(
      duration: duration,
      curve: Curves.easeOutCubic,
      alignment: Alignment.bottomRight,
      child: AnimatedSwitcher(
        duration: duration,
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.bottomRight,
          children: [...previous, if (current != null) current],
        ),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: .88, end: 1).animate(animation),
            alignment: Alignment.bottomRight,
            child: child,
          ),
        ),
        child: child,
      ),
    );
  }
}
