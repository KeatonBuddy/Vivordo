import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/vivordo_theme.dart';

@immutable
class ScreenInsight {
  const ScreenInsight(
    this.screen,
    this.title,
    this.message, {
    this.context,
    this.onAction,
    this.actionLabel,
    this.busy = false,
  });
  final VoidCallback? onAction;
  final String? actionLabel;
  final bool busy;
  final String? context;
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

  /// Opens Vivordo AI about an insight, as the insight bar does; set by the
  /// main navigation.
  void Function(ScreenInsight insight)? onAsk;

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
        old?.$2.message == insight.message &&
        old?.$2.context == insight.context &&
        old?.$2.busy == insight.busy &&
        old?.$2.actionLabel == insight.actionLabel &&
        old?.$2.onAction == insight.onAction) {
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

/// Opens Vivordo AI about an insight from a screen inside the main tabs; null
/// where there's no chat to open. Look it up before pushing a root sheet:
/// those sit outside the tabs.
void Function(ScreenInsight insight)? vivordoAiAsker(BuildContext context) =>
    context
        .getInheritedWidgetOfExactType<ScreenInsightScope>()
        ?.controller
        .onAsk;

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

class _ContextualInsightBarState extends State<ContextualInsightBar>
    with SingleTickerProviderStateMixin {
  /// Width of the collapsed robot button, which the pill grows out of.
  static const _buttonSize = 64.0;

  bool _dismissed = false;
  Timer? _delay;
  bool _ready = false;
  bool _expanded = false;
  // Kept while the pill closes, so its content can shrink back into the
  // button after the insight itself has gone.
  ScreenInsight? _shown;
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 340),
  );
  late final Animation<double> _width = CurvedAnimation(
    parent: _reveal,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  // Content fades in once the pill has room for it, and out first on close.
  late final Animation<double> _content = CurvedAnimation(
    parent: _reveal,
    curve: const Interval(.45, 1, curve: Curves.easeOut),
    reverseCurve: const Interval(.55, 1, curve: Curves.easeIn),
  );

  bool get _open =>
      _ready && widget.insight != null && !widget.suppressed && !_dismissed;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reveal.duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 340);
  }

  void _schedule() {
    _delay?.cancel();
    _ready = false;
    _expanded = false;
    _sync();
    if (widget.insight == null || widget.suppressed) return;
    _delay = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => _ready = true);
      _sync();
    });
  }

  /// Drives the morph toward the current open/closed state.
  void _sync() {
    if (_open) {
      _shown = widget.insight;
      _reveal.forward();
    } else {
      _expanded = false;
      _reveal.reverse();
    }
  }

  void _dismiss() {
    setState(() => _dismissed = true);
    _sync();
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
    } else if (_open) {
      _shown = widget.insight; // same screen, refreshed text
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final fullWidth = constraints.maxWidth;
        return Align(
          alignment: Alignment.bottomRight,
          child: AnimatedBuilder(
            animation: _reveal,
            builder: (context, _) {
              final t = _width.value;
              final insight = _shown;
              final showContent = _reveal.value > 0 && insight != null;
              return SizedBox(
                width: _buttonSize + (fullWidth - _buttonSize) * t,
                child: Material(
                  // The pill is the button stretched open: same spot, same
                  // corner radius, taking on the card colour as it widens.
                  color: Color.lerp(VivordoTheme.brand, colors.card, t),
                  // Collapsed, the pill carries the button's purple glow,
                  // which its clip would otherwise cut off.
                  elevation: 10 - 2 * t,
                  shadowColor: Color.lerp(
                    VivordoTheme.brand.withValues(alpha: .38),
                    Colors.black,
                    t,
                  ),
                  animationDuration: Duration.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(_buttonSize / 2),
                    side: BorderSide(
                      color: VivordoTheme.brand.withValues(alpha: t),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: AnimatedSize(
                    duration: _reveal.duration!,
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.bottomCenter,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(context).height * .45,
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              height: _buttonSize,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: showContent
                                        ? ClipRect(
                                            // Laid out at full width and
                                            // uncovered as the pill widens,
                                            // so nothing reflows mid-motion.
                                            child: OverflowBox(
                                              alignment: Alignment.centerRight,
                                              minWidth: fullWidth - _buttonSize,
                                              maxWidth: fullWidth - _buttonSize,
                                              child: FadeTransition(
                                                opacity: _content,
                                                child: _header(insight),
                                              ),
                                            ),
                                          )
                                        : const SizedBox.shrink(),
                                  ),
                                  SizedBox.square(
                                    dimension: _buttonSize,
                                    child: Center(child: widget.collapsed),
                                  ),
                                ],
                              ),
                            ),
                            if (_expanded && insight != null) _details(insight),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _header(ScreenInsight insight) {
    final colors = context.vivordoColors;
    return Row(
      children: [
        const SizedBox(width: 16),
        Expanded(
          child: InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
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
          tooltip: _expanded ? 'Collapse insight' : 'Expand insight',
          onPressed: () => setState(() => _expanded = !_expanded),
          icon: Icon(_expanded ? Icons.expand_more : Icons.expand_less),
        ),
        IconButton(
          tooltip: 'Dismiss insights for this screen',
          onPressed: _dismiss,
          icon: const Icon(Icons.close, size: 20),
        ),
      ],
    );
  }

  Widget _details(ScreenInsight insight) {
    final colors = context.vivordoColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(insight.message, style: TextStyle(color: colors.textPrimary)),
          const SizedBox(height: 8),
          Text(
            'Based on the data shown on this screen. Wellness guidance, not medical advice.',
            style: TextStyle(fontSize: 12, color: colors.textSecondary),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: insight.busy
                ? null
                : insight.onAction ?? () => widget.onAsk(insight.prompt),
            icon: const Icon(Icons.chat_bubble_outline),
            label: Text(insight.actionLabel ?? 'Ask Vivordo AI'),
          ),
        ],
      ),
    );
  }
}
