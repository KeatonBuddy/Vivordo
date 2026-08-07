import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'home_screen.dart';
import 'scan_screen.dart';
import 'dashboard_screen.dart';
import 'panda_screen.dart';
import 'fitness_screen.dart';
import 'my_day_screen.dart';
import '../src/services/analytics_service.dart';
import '../src/services/circle_profile_service.dart';
import '../src/services/health_service.dart';
import '../theme/vivordo_theme.dart';

class MainNavigationScreen extends StatefulWidget {
  final int initialIndex;
  const MainNavigationScreen({super.key, this.initialIndex = 0});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  late int _selectedIndex;
  late bool _pandaHasBeenOpened;
  late final AnimationController _chatRevealController;
  late final AnimationController _fitnessPulseController;
  late final Animation<double> _chatRevealAnimation;
  final GlobalKey _chatBubbleKey = GlobalKey();
  Offset _chatRevealOrigin = Offset.zero;
  bool _chatOpen = false;
  bool _startupSplashMounted = true;
  Timer? _healthRefreshTimer;
  final List<Timer> _tabPreloadTimers = [];
  Future<void>? _circlePreload;
  final Set<int> _loadedTabs = {};
  late final List<Widget> _tabPages;
  late final PandaScreen _persistentChatScreen;
  final Color primaryPurple = VivordoTheme.brand;

  /// Analytics screen name per tab index, aligned with the nav bar order.
  static const List<String> _screenNames = [
    'home',
    'my_day',
    'scan',
    'fitness',
    'metrics',
    'ai_chat',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _selectedIndex = widget.initialIndex == 5
        ? 0
        : widget.initialIndex.clamp(0, 4);
    _loadedTabs.add(_selectedIndex);
    _tabPages = [
      const SizedBox.shrink(),
      const MyDayScreen(),
      const SizedBox.shrink(),
      const FitnessScreen(),
      DashboardScreen(onScanTap: _openScan),
    ];
    _persistentChatScreen = PandaScreen(onClose: _closeChat);
    _pandaHasBeenOpened = widget.initialIndex == 5;
    _chatRevealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
      reverseDuration: const Duration(milliseconds: 360),
    );
    _fitnessPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    );
    FitnessWorkoutTimerState.isRunning.addListener(_syncFitnessPulse);
    _syncFitnessPulse();
    unawaited(FitnessWorkoutTimerState.restore());
    _chatRevealAnimation = CurvedAnimation(
      parent: _chatRevealController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _logScreenView(_selectedIndex);
    _refreshTodayFromHealth();
    _circlePreload = CircleProfileService.preload();
    // HealthKit does not push new values into Firestore. Keep the shared data
    // source current for both Home and Dashboard while the app is in use.
    _healthRefreshTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _refreshTodayFromHealth(),
    );
    if (widget.initialIndex == 5) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openChat());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _preloadTabs());
  }

  void _refreshTodayFromHealth() {
    if (FirebaseAuth.instance.currentUser == null) return;
    HealthService().syncToday().catchError((Object error) {
      debugPrint('MainNavigation: Apple Health refresh failed: $error');
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshTodayFromHealth();
  }

  @override
  void dispose() {
    _healthRefreshTimer?.cancel();
    for (final timer in _tabPreloadTimers) {
      timer.cancel();
    }
    _chatRevealController.dispose();
    FitnessWorkoutTimerState.isRunning.removeListener(_syncFitnessPulse);
    _fitnessPulseController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _syncFitnessPulse() {
    if (FitnessWorkoutTimerState.isRunning.value) {
      if (!_fitnessPulseController.isAnimating) {
        _fitnessPulseController.repeat(reverse: true);
      }
    } else {
      _fitnessPulseController.stop();
      _fitnessPulseController.value = 0;
    }
    if (mounted) setState(() {});
  }

  /// Switches to [index] and records the screen view. All tab changes route
  /// through here so analytics stay in sync with what's on screen.
  void _selectTab(int index) {
    if (index < 0 || index >= _tabPages.length) return;
    if (index != _selectedIndex) _logScreenView(index);
    setState(() {
      _loadedTabs.add(index);
      _selectedIndex = index;
    });
  }

  void _preloadTabs() {
    var delay = 150;
    for (var index = 0; index < _tabPages.length; index++) {
      if (_loadedTabs.contains(index)) continue;
      _tabPreloadTimers.add(
        Timer(Duration(milliseconds: delay), () {
          if (!mounted || _loadedTabs.contains(index)) return;
          setState(() => _loadedTabs.add(index));
        }),
      );
      delay += 150;
    }
    if (!_pandaHasBeenOpened) {
      _tabPreloadTimers.add(
        Timer(Duration(milliseconds: delay), () {
          if (!mounted || _pandaHasBeenOpened) return;
          setState(() => _pandaHasBeenOpened = true);
        }),
      );
    }
    _tabPreloadTimers.add(
      // Give the newly mounted Firebase-backed screens time to receive their
      // first snapshots before starting the transition. This prevents their
      // initial layout work from competing with the fade animation.
      Timer(Duration(milliseconds: delay + 1200), () async {
        await _circlePreload?.timeout(
          const Duration(seconds: 5),
          onTimeout: () {},
        );
        await WidgetsBinding.instance.endOfFrame;
        if (mounted) setState(() => _startupSplashMounted = false);
      }),
    );
  }

  void _openChat() {
    if (_chatOpen) return;
    final bubbleContext = _chatBubbleKey.currentContext;
    final bubbleBox = bubbleContext?.findRenderObject() as RenderBox?;
    final origin = bubbleBox == null
        ? Offset(
            MediaQuery.sizeOf(context).width - 64,
            MediaQuery.sizeOf(context).height - 150,
          )
        : bubbleBox.localToGlobal(bubbleBox.size.center(Offset.zero));
    setState(() {
      _chatRevealOrigin = origin;
      _pandaHasBeenOpened = true;
      _chatOpen = true;
    });
    _logScreenView(5);
    _chatRevealController.forward(from: 0);
  }

  Future<void> _closeChat() async {
    if (!_chatOpen) return;
    await _chatRevealController.reverse();
    if (mounted) setState(() => _chatOpen = false);
  }

  void _logScreenView(int index) {
    if (index >= 0 && index < _screenNames.length) {
      AnalyticsService().logScreenView(_screenNames[index]);
    }
  }

  void _openScan() => _selectTab(2);

  @override
  Widget build(BuildContext context) {
    final activePage = IndexedStack(
      index: _selectedIndex,
      children: List.generate(
        _tabPages.length,
        (index) => _loadedTabs.contains(index)
            ? KeyedSubtree(
                key: ValueKey('main-tab-$index'),
                child: switch (index) {
                  0 => HomeScreen(
                    onScanTap: _openScan,
                    onFitnessTap: () => _selectTab(3),
                    revealStress: !_startupSplashMounted,
                  ),
                  2 => ScanScreen(
                    isActive: _selectedIndex == 2 && !_chatOpen,
                    onBackToHome: () => _selectTab(0),
                  ),
                  _ => _tabPages[index],
                },
              )
            : const SizedBox.shrink(),
      ),
    );

    return PopScope(
      canPop: !_chatOpen,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _chatOpen) _closeChat();
      },
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(child: RepaintBoundary(child: activePage)),
            Positioned(
              bottom: 30,
              left: 24,
              right: 24,
              child: _buildFloatingNavBar(),
            ),
            Positioned(
              key: const ValueKey('ai-chat-bubble-layer'),
              right: 30,
              bottom: 116,
              child: IgnorePointer(
                ignoring: _chatOpen,
                child: AnimatedOpacity(
                  opacity: _chatOpen ? 0 : 1,
                  duration: const Duration(milliseconds: 140),
                  child: _buildChatBubble(),
                ),
              ),
            ),
            if (_pandaHasBeenOpened)
              Positioned.fill(
                key: const ValueKey('persistent-ai-chat-layer'),
                child: IgnorePointer(
                  ignoring: !_chatOpen,
                  child: AnimatedBuilder(
                    animation: _chatRevealAnimation,
                    // Reuse one mounted chat instance so closing the circular
                    // reveal never resets the current conversation.
                    child: _persistentChatScreen,
                    builder: (context, child) => ClipPath(
                      clipper: _CircularRevealClipper(
                        origin: _chatRevealOrigin,
                        progress: _chatRevealAnimation.value,
                      ),
                      child: child,
                    ),
                  ),
                ),
              ),
            if (_startupSplashMounted)
              Positioned.fill(
                child: AbsorbPointer(
                  child: RepaintBoundary(
                    child: ColoredBox(
                      color: context.vivordoColors.page,
                      child: Center(
                        child: Image.asset(
                          'assets/vivordo_splash_logo_full.png',
                          width: 220,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatBubble() => Material(
    key: _chatBubbleKey,
    color: primaryPurple,
    elevation: 10,
    shadowColor: primaryPurple.withValues(alpha: .38),
    shape: const CircleBorder(),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: _openChat,
      child: const SizedBox(
        width: 64,
        height: 64,
        child: Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 30),
      ),
    ),
  );

  Widget _buildFloatingNavBar() {
    final colors = context.vivordoColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final glassSettings = LiquidGlassSettings(
      refractiveIndex: 1.16,
      thickness: 22,
      blur: 10,
      chromaticAberration: .006,
      saturation: isDark ? 1.25 : 1.4,
      lightIntensity: isDark ? .55 : .9,
      ambientStrength: isDark ? .18 : .4,
      lightAngle: math.pi / 4,
      glassColor: isDark
          ? colors.card.withValues(alpha: .48)
          : Colors.white.withValues(alpha: .42),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: colors.shadow,
            blurRadius: 20,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: LiquidGlassLayer(
        settings: glassSettings,
        child: LiquidGlass(
          shape: const LiquidRoundedSuperellipse(borderRadius: 24),
          clipBehavior: Clip.antiAlias,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Colors.white.withValues(alpha: isDark ? .14 : .68),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _navItem(Icons.home_rounded, "Home", 0),
                  _navItem(Icons.calendar_month_rounded, "My Day", 1),
                  _navItem(Icons.fingerprint_rounded, "Scan", 2),
                  _navItem(Icons.fitness_center_rounded, "Fitness", 3),
                  _navItem(Icons.bar_chart_rounded, "Metrics", 4),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _navItem(IconData icon, String label, int index) {
    bool isActive = _selectedIndex == index;
    final isWorkoutPulse =
        index == 3 && FitnessWorkoutTimerState.isRunning.value;
    return InkWell(
      onTap: () => _selectTab(index),
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: isActive ? primaryPurple : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isWorkoutPulse)
              AnimatedBuilder(
                animation: _fitnessPulseController,
                builder: (context, child) {
                  final pulse = _fitnessPulseController.value;
                  return Transform.scale(
                    scale: 1 + (pulse * .18),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: primaryPurple.withValues(
                              alpha: .16 + (pulse * .34),
                            ),
                            blurRadius: 5 + (pulse * 10),
                            spreadRadius: pulse * 2,
                          ),
                        ],
                      ),
                      child: Icon(
                        icon,
                        color: isActive ? Colors.white : primaryPurple,
                        size: 23,
                      ),
                    ),
                  );
                },
              )
            else
              Icon(
                icon,
                color: isActive
                    ? Colors.white
                    : index == 2
                    ? primaryPurple
                    : context.vivordoColors.textSecondary,
                size: 23,
              ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: isActive
                    ? Colors.white
                    : index == 2
                    ? primaryPurple
                    : context.vivordoColors.textSecondary,
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CircularRevealClipper extends CustomClipper<Path> {
  const _CircularRevealClipper({required this.origin, required this.progress});

  final Offset origin;
  final double progress;

  @override
  Path getClip(Size size) {
    final horizontal = math.max(origin.dx, size.width - origin.dx);
    final vertical = math.max(origin.dy, size.height - origin.dy);
    final radius = math.sqrt(horizontal * horizontal + vertical * vertical);
    return Path()
      ..addOval(Rect.fromCircle(center: origin, radius: radius * progress));
  }

  @override
  bool shouldReclip(covariant _CircularRevealClipper oldClipper) =>
      oldClipper.origin != origin || oldClipper.progress != progress;
}
