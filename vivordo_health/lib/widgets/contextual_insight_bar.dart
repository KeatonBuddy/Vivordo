import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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

  /// Goes to a tab or screen by name ('fitness', 'sleep'…), as Vivordo AI's
  /// links do; set by the main navigation.
  void Function(String screen)? onOpen;

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

/// Goes to a main tab or screen by name from a screen inside the tabs, or
/// null where there are none.
void Function(String screen)? vivordoScreenOpener(BuildContext context) =>
    context
        .getInheritedWidgetOfExactType<ScreenInsightScope>()
        ?.controller
        .onOpen;

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

/// Which insight each screen last showed and whether the robot has waved
/// about it, so an insight opens by itself only once: later visits show a
/// dot on the button instead. Kept on the device with [persist].
class InsightMemory {
  InsightMemory({this.persist = false});

  /// The app's memory, saved between launches.
  static final shared = InsightMemory(persist: true);

  final bool persist;
  static const _storage = FlutterSecureStorage();
  static const _key = 'seen_insights_v1';
  Map<String, dynamic> _seen = {};
  Future<void>? _loading;

  Future<void> load() => _loading ??= () async {
    if (!persist) return;
    try {
      final saved = await _storage.read(key: _key);
      if (saved != null) _seen = {...jsonDecode(saved) as Map, ..._seen};
    } catch (error) {
      debugPrint('InsightMemory: load failed: $error');
    }
  }();

  bool seen(ScreenInsight insight) =>
      (_seen[insight.screen] as Map?)?['message'] == insight.message;

  bool waved(ScreenInsight insight) =>
      seen(insight) && (_seen[insight.screen] as Map)['waved'] == true;

  void markSeen(ScreenInsight insight) =>
      _write(insight.screen, {'message': insight.message, 'waved': false});

  void markWaved(ScreenInsight insight) =>
      _write(insight.screen, {'message': insight.message, 'waved': true});

  void _write(String screen, Map<String, Object> value) {
    _seen[screen] = value;
    if (!persist) return;
    unawaited(
      _storage.write(key: _key, value: jsonEncode(_seen)).catchError((
        Object error,
      ) {
        debugPrint('InsightMemory: save failed: $error');
      }),
    );
  }
}

/// The Vivordo AI button beside the tab bar, and the screen's insight.
/// A new insight plays once by itself: the button rises above the tab bar
/// (reporting how far through [lift], so the bar can widen into the space),
/// then opens into a pill. An insight already seen leaves a dot on the
/// button, the robot waves the first time that happens, and tapping the
/// button opens it. Without an insight the button calls [onButtonTap].
class ContextualInsightBar extends StatefulWidget {
  const ContextualInsightBar({
    super.key,
    required this.insight,
    required this.button,
    required this.onButtonTap,
    required this.onAsk,
    this.suppressed = false,
    this.lift,
    this.memory,
  });
  final ScreenInsight? insight;

  /// The round button; [waves] counts up each time the robot should wave.
  final Widget Function(BuildContext context, int waves) button;
  final ValueChanged<BuildContext> onButtonTap;
  final ValueChanged<String> onAsk;
  final bool suppressed;
  final ValueNotifier<double>? lift;
  final InsightMemory? memory;

  /// The button's size, matching the tab bar's height.
  static const buttonSize = 62.0;

  /// How far the button rises: above the tab bar, with a gap.
  static const rise = buttonSize + 10;

  @override
  State<ContextualInsightBar> createState() => _ContextualInsightBarState();
}

class _ContextualInsightBarState extends State<ContextualInsightBar>
    with TickerProviderStateMixin {
  static const _buttonSize = ContextualInsightBar.buttonSize;

  late final InsightMemory _memory = widget.memory ?? InsightMemory.shared;
  Timer? _delay;
  bool _wantOpen = false;
  bool _expanded = false;
  int _waves = 0;
  // Touches on screen; the button waits for none before it moves, so the
  // tab bar never shifts under a finger.
  final Set<int> _pointers = {};
  // Kept while the pill closes, so its content can shrink back into the
  // button after the insight itself has gone.
  ScreenInsight? _shown;
  late final AnimationController _lift = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  )..addListener(() => widget.lift?.value = _liftCurve.value);
  late final Animation<double> _liftCurve = CurvedAnimation(
    parent: _lift,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
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

  bool get _open => _wantOpen && widget.insight != null && !widget.suppressed;

  /// Only for an insight already seen; a new one opens by itself instead.
  bool get _dot {
    final insight = widget.insight;
    return insight != null &&
        !widget.suppressed &&
        !_wantOpen &&
        _memory.seen(insight);
  }

  @override
  void initState() {
    super.initState();
    GestureBinding.instance.pointerRouter.addGlobalRoute(_trackPointer);
    unawaited(_memory.load().then((_) => mounted ? setState(() {}) : null));
    _schedule();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.disableAnimationsOf(context);
    _reveal.duration = still
        ? Duration.zero
        : const Duration(milliseconds: 340);
    _lift.duration = still ? Duration.zero : const Duration(milliseconds: 300);
  }

  void _trackPointer(PointerEvent event) {
    if (event is PointerDownEvent) _pointers.add(event.pointer);
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      _pointers.remove(event.pointer);
    }
  }

  /// Arriving on a screen: a new insight opens by itself after a moment;
  /// a seen one gets a wave the first time its dot shows.
  void _schedule() {
    _delay?.cancel();
    _wantOpen = false;
    _expanded = false;
    _sync();
    final insight = widget.insight;
    if (insight == null || widget.suppressed) return;
    _delay = Timer(const Duration(seconds: 2), () async {
      await _memory.load();
      // Not while a finger is down.
      while (mounted && _pointers.isNotEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      if (!mounted || widget.insight != insight || widget.suppressed) return;
      if (!_memory.seen(insight)) {
        _memory.markSeen(insight);
        setState(() => _wantOpen = true);
        _sync();
      } else if (!_memory.waved(insight)) {
        _memory.markWaved(insight);
        setState(() => _waves++);
      }
    });
  }

  /// Drives the motion toward the current open/closed state: rise, then
  /// open; close, then settle back beside the tab bar.
  void _sync() {
    if (_open) {
      _shown = widget.insight;
      unawaited(
        _lift.forward().orCancel.then((_) {
          if (mounted && _open) unawaited(_reveal.forward());
        }, onError: (_) {}),
      );
    } else {
      _expanded = false;
      unawaited(
        _reveal.reverse().orCancel.then((_) {
          if (mounted && !_open) unawaited(_lift.reverse());
        }, onError: (_) {}),
      );
    }
  }

  void _dismiss() {
    setState(() => _wantOpen = false);
    _sync();
  }

  void _tapButton(BuildContext buttonContext) {
    if (_dot) {
      setState(() => _wantOpen = true);
      _sync();
      return;
    }
    widget.onButtonTap(buttonContext);
  }

  @override
  void didUpdateWidget(covariant ContextualInsightBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.insight?.screen != widget.insight?.screen ||
        oldWidget.suppressed != widget.suppressed) {
      _schedule();
    } else if (_open) {
      _shown = widget.insight; // same screen, refreshed text
    }
  }

  @override
  void dispose() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_trackPointer);
    _delay?.cancel();
    _lift.dispose();
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
            animation: Listenable.merge([_reveal, _lift]),
            builder: (context, _) {
              final t = _width.value;
              final insight = _shown;
              final showContent = _reveal.value > 0 && insight != null;
              return Padding(
                padding: EdgeInsets.only(
                  bottom: ContextualInsightBar.rise * _liftCurve.value,
                ),
                child: SizedBox(
                  width: _buttonSize + (fullWidth - _buttonSize) * t,
                  child: Material(
                    // The pill is the button stretched open: same spot, same
                    // corner radius, taking on the card colour as it widens.
                    color: colors.card.withValues(alpha: t),
                    elevation: 8 * t,
                    shadowColor: Colors.black,
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
                                                alignment:
                                                    Alignment.centerRight,
                                                minWidth:
                                                    fullWidth - _buttonSize,
                                                maxWidth:
                                                    fullWidth - _buttonSize,
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
                                      child: _buttonWithDot(),
                                    ),
                                  ],
                                ),
                              ),
                              if (_expanded && insight != null)
                                _details(insight),
                            ],
                          ),
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

  Widget _buttonWithDot() => Builder(
    builder: (buttonContext) => Semantics(
      button: true,
      label: _dot ? 'Vivordo AI, insight available' : 'Vivordo AI',
      child: GestureDetector(
        onTap: () => _tapButton(buttonContext),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: widget.button(buttonContext, _waves)),
            if (_dot)
              // Inside the round button's edge, which clips.
              Positioned(
                top: 7,
                right: 7,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: VivordoTheme.brand,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );

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
