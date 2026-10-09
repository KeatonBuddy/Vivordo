import 'dart:async';
import '../widgets/app_tour.dart';
import '../widgets/contextual_insight_bar.dart';
import '../widgets/vivordo_robot.dart';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'home_screen.dart';
import 'scan_screen.dart';
import 'dashboard_screen.dart';
import 'assistant_screen.dart';
import 'heart_rate_detail_screen.dart';
import 'mood_detail_screen.dart';
import 'physical_health_screen.dart';
import 'sleep_detail_screen.dart';
import 'stress_detail_screen.dart';
import 'fitness_screen.dart';
import 'my_day_screen.dart';
import '../src/services/achievement_service.dart';
import '../src/services/analytics_service.dart';
import '../src/services/circle_profile_service.dart';
import '../src/services/day_record_service.dart';
import '../src/services/vo2_max_service.dart';
import '../src/services/health_service.dart';
import '../theme/vivordo_theme.dart';

class MainNavigationScreen extends StatefulWidget {
  final int initialIndex;
  final bool openMoodCheckIn;

  /// `tours` from the user document: which screen tours have been seen.
  final Map<String, dynamic>? seenTours;
  const MainNavigationScreen({
    super.key,
    this.initialIndex = 0,
    this.openMoodCheckIn = false,
    this.seenTours,
  });

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
  final GlobalKey<NavigatorState> _contentNavigatorKey =
      GlobalKey<NavigatorState>();
  late final _ContentNavigatorObserver _contentNavigatorObserver;
  final _insights = ScreenInsightController();
  final _contextPrompt = ValueNotifier<ScreenInsight?>(null);
  // Asked from a screen's insight bar, the chat rises as a sheet over that
  // screen; the robot button (or expanding the sheet) shows the full thread.
  final _chatSheet = ValueNotifier<bool>(false);
  Offset _chatRevealOrigin = Offset.zero;
  bool _chatOpen = false;
  bool _detailRouteOpen = false;
  bool _startupSplashMounted = true;

  /// The screen whose tour is running, if any.
  String? _tourScreen;
  bool _tourShowsChat = false;
  late final Map<String, dynamic> _seenTours = {...?widget.seenTours};
  final GlobalKey _navBarKey = GlobalKey();
  final GlobalKey _chatLayerKey = GlobalKey();
  final GlobalKey _homeRightNowKey = GlobalKey();
  final GlobalKey _homeVitalsKey = GlobalKey();
  final GlobalKey _homeCircleKey = GlobalKey();
  final GlobalKey _homeYourDayKey = GlobalKey();
  final GlobalKey _homeInsightsKey = GlobalKey();
  final GlobalKey _myDayActionsKey = GlobalKey();
  final GlobalKey _myDayBriefKey = GlobalKey();
  final GlobalKey _myDayNowKey = GlobalKey();
  final GlobalKey _myDayPrioritiesKey = GlobalKey();
  final GlobalKey _myDayTimelineKey = GlobalKey();
  final GlobalKey _myDayTomorrowKey = GlobalKey();
  final GlobalKey _scanHelpKey = GlobalKey();
  final GlobalKey _scanStartKey = GlobalKey();
  final GlobalKey _scanHowKey = GlobalKey();
  final GlobalKey _fitnessActionsKey = GlobalKey();
  final GlobalKey _fitnessRingsKey = GlobalKey();
  final GlobalKey _fitnessButtonsKey = GlobalKey();
  final GlobalKey _fitnessWeekKey = GlobalKey();
  final GlobalKey _fitnessRecentKey = GlobalKey();
  final GlobalKey _fitnessBodyKey = GlobalKey();
  final GlobalKey _metricsCustomizeKey = GlobalKey();
  final GlobalKey _metricsPhysicalKey = GlobalKey();
  final GlobalKey _metricsKeyMetricsKey = GlobalKey();
  final GlobalKey _metricsInsightsKey = GlobalKey();
  Timer? _healthRefreshTimer;
  final List<Timer> _tabPreloadTimers = [];
  Future<void>? _circlePreload;
  AchievementMonitor? _achievementMonitor;
  final Set<int> _loadedTabs = {};
  late final List<ValueNotifier<bool>> _tabActivity;
  late final ValueNotifier<bool> _homeStressReveal;
  late final List<Widget> _tabPages;
  late final AssistantScreen _persistentChatScreen;
  final Color primaryPurple = VivordoTheme.brand;
  LiquidGlassSettings? _cachedGlassSettings;
  bool? _cachedGlassSettingsIsDark;

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
    _tabActivity = List.generate(
      5,
      (index) => ValueNotifier<bool>(
        widget.initialIndex != 5 && index == _selectedIndex,
      ),
    );
    _homeStressReveal = ValueNotifier<bool>(false);
    _contentNavigatorObserver = _ContentNavigatorObserver(
      _handleContentNavigationChanged,
    );
    _tabPages = List.generate(5, _buildCachedTabPage);
    _persistentChatScreen = AssistantScreen(
      onClose: _closeChat,
      contextPrompt: _contextPrompt,
      onOpenScreen: _openFromAssistant,
      sheet: _chatSheet,
      onExpand: () => setState(() => _chatSheet.value = false),
    );
    _insights.onAsk = _askAbout;
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
    // Yesterday too, in case the app was last opened before it ended.
    unawaited(DayRecordService.syncOnOpen());
    _circlePreload = CircleProfileService.preload();
    _achievementMonitor = AchievementMonitor.start();
    // HealthKit does not push new values into Firestore. Keep the shared data
    // source current for both Home and Dashboard while the app is in use.
    // A full sync walks every consented metric, so keep the interval long and
    // skip it while backgrounded — resuming triggers its own refresh below.
    _healthRefreshTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        return;
      }
      _refreshTodayFromHealth();
    });
    if (widget.initialIndex == 5) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openChat());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _preloadTabs());
    AppTour.replayRequested.addListener(_replayTour);
  }

  Future<void> _replayTour() async {
    if (!AppTour.replayRequested.value || !mounted) return;
    AppTour.replayRequested.value = false;
    _seenTours.clear();
    unawaited(resetTours());
    _contentNavigatorKey.currentState?.popUntil((route) => route.isFirst);
    await _closeChat();
    // The route observer clears the detail flag after this frame.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    _selectTab(0);
    _maybeStartTour('home');
  }

  /// Starts [screen]'s tour if it has one, hasn't been seen, and nothing
  /// else needs the screen right now.
  void _maybeStartTour(String screen) {
    if (_tourScreen != null ||
        _chatOpen ||
        _detailRouteOpen ||
        FitnessWorkoutTimerState.isRunning.value ||
        !needsTour(_seenTours, screen) ||
        !_tourScripts.containsKey(screen)) {
      return;
    }
    setState(() => _tourScreen = screen);
  }

  void _finishTour() {
    final screen = _tourScreen;
    if (screen == null) return;
    _seenTours[screen] = kTourVersion;
    setState(() {
      _tourScreen = null;
      _tourShowsChat = false;
    });
    unawaited(markTourSeen(screen));
  }

  /// One short tour per screen, run the first time that screen is shown.
  /// Steps spotlight widgets through keys passed into the screen.
  late final Map<String, List<TourStep>> _tourScripts = {
    'home': [
      const TourStep(
        "Hi, I'm Vivordo AI. Let me show you around Home. It takes about "
        'thirty seconds.',
      ),
      TourStep(
        'This is your stress right now. It updates whenever new information '
        'comes in, and tapping it opens the full picture.',
        target: _homeRightNowKey,
      ),
      TourStep(
        "Last night's sleep, your latest heart rate and today's mood. Tap "
        'any of them for more.',
        target: _homeVitalsKey,
      ),
      TourStep(
        'Circle is your friends. Share progress, cheer each other on and '
        'take on challenges together.',
        target: _homeCircleKey,
      ),
      TourStep(
        'Your Day reads your calendar against your energy and shows where '
        'the day will push you. Open My Day for the full plan.',
        target: _homeYourDayKey,
      ),
      TourStep(
        'Insights are the small things I notice in your sleep, heart rate '
        'and schedule. They change as the day goes on.',
        target: _homeInsightsKey,
      ),
      TourStep(
        'Everything else lives down here: My Day, Scan, Fitness and Metrics.',
        target: _navBarKey,
      ),
      TourStep(
        "And I'm right here. I'll leave notes as I spot things, and you can "
        'ask me anything.',
        target: _chatLayerKey,
        // The layer spans the screen; the button is its right end.
        crop: (layer) =>
            Rect.fromLTWH(layer.right - 64, layer.bottom - 64, 64, 64),
        pose: RobotPose.celebrate,
      ),
    ],
    // Order follows the page top to bottom: My Day is a lazy list, so a
    // section scrolled far off screen has no widget to point at.
    'my_day': [
      const TourStep(
        'This is My Day: your calendar and priorities, planned around your '
        'energy.',
      ),
      TourStep(
        'The book is your journal, and the calendar opens the month view.',
        target: _myDayActionsKey,
      ),
      TourStep(
        "Your daily brief: how today has gone, and tomorrow's Demand "
        'against your Capacity.',
        target: _myDayBriefKey,
      ),
      TourStep(
        "Now is what's happening at the moment, and what's up next.",
        target: _myDayNowKey,
      ),
      TourStep(
        'Priorities are the few things you want done today. Add one and '
        'plan it into a slot.',
        target: _myDayPrioritiesKey,
      ),
      TourStep(
        "Today's timeline lays out your events. The plus adds one straight "
        'to your calendar.',
        target: _myDayTimelineKey,
      ),
      TourStep(
        "Tomorrow's preview shows what's already planned, so you can "
        'lighten it the evening before.',
        target: _myDayTomorrowKey,
        pose: RobotPose.celebrate,
      ),
    ],
    'scan': [
      const TourStep(
        'This is the Scan. Fifteen seconds with a fingertip on the camera '
        'gives me your heart rate.',
      ),
      TourStep(
        'The question mark replays the fingertip tutorial whenever you need '
        'it.',
        target: _scanHelpKey,
      ),
      TourStep(
        'Tap Start Scan, cover the rear camera and flash with your '
        "fingertip, and hold still until it's done.",
        target: _scanStartKey,
      ),
      TourStep(
        'How it works walks through the four steps, and the tips below help '
        'you get a clean reading.',
        target: _scanHowKey,
        pose: RobotPose.celebrate,
      ),
    ],
    'fitness': [
      const TourStep(
        'This is Fitness: your activity, workouts and body in one place.',
      ),
      TourStep(
        'Your workout streak, and the target icon sets your activity and '
        'strength goals.',
        target: _fitnessActionsKey,
      ),
      TourStep(
        "Today's rings: steps, calories and exercise minutes against your "
        'goals. Tap them for the month.',
        target: _fitnessRingsKey,
      ),
      TourStep(
        "Start a workout with a live timer, or log something you've already "
        'done.',
        target: _fitnessButtonsKey,
      ),
      TourStep(
        'This week counts your workouts and active days, alongside your '
        'strength goals.',
        target: _fitnessWeekKey,
      ),
      TourStep(
        "Recent is everything you've logged. See all opens the full history.",
        target: _fitnessRecentKey,
      ),
      TourStep(
        'Body keeps your weight, BMI and body fat up to date.',
        target: _fitnessBodyKey,
        pose: RobotPose.celebrate,
      ),
    ],
    'metrics': [
      const TourStep(
        'This is Metrics: every measurement I track, with a detail screen '
        'behind each one.',
      ),
      TourStep(
        'Customize picks which metrics show here and in what order.',
        target: _metricsCustomizeKey,
      ),
      TourStep(
        'Physical Health sums up the last four weeks of activity, strength, '
        'cardio fitness and sleep. Tap it for the breakdown.',
        target: _metricsPhysicalKey,
      ),
      TourStep(
        'Key metrics are your trends at a glance. Tap any tile to go deeper.',
        target: _metricsKeyMetricsKey,
      ),
      TourStep(
        'Insights compare your steps and stress over the week.',
        target: _metricsInsightsKey,
        pose: RobotPose.celebrate,
      ),
    ],
  };

  void _refreshTodayFromHealth() {
    if (FirebaseAuth.instance.currentUser == null) return;
    HealthService().syncToday().catchError((Object error) {
      debugPrint('MainNavigation: Apple Health refresh failed: $error');
    });
    // Apple Watch VO₂ max for Physical Health (throttled inside).
    unawaited(Vo2MaxService.sync());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshTodayFromHealth();
      _achievementMonitor?.scheduleNow();
      unawaited(DayRecordService.syncOnOpen());
    }
  }

  @override
  void dispose() {
    _healthRefreshTimer?.cancel();
    unawaited(_achievementMonitor?.dispose() ?? Future<void>.value());
    for (final timer in _tabPreloadTimers) {
      timer.cancel();
    }
    _chatRevealController.dispose();
    AppTour.replayRequested.removeListener(_replayTour);
    FitnessWorkoutTimerState.isRunning.removeListener(_syncFitnessPulse);
    _fitnessPulseController.dispose();
    for (final activity in _tabActivity) {
      activity.dispose();
    }
    _homeStressReveal.dispose();
    _insights.dispose();
    _contextPrompt.dispose();
    _chatSheet.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Widget _buildCachedTabPage(int index) {
    return KeyedSubtree(
      key: ValueKey('main-tab-$index'),
      child: ValueListenableBuilder<bool>(
        valueListenable: _tabActivity[index],
        builder: (context, isActive, _) {
          final page = switch (index) {
            0 => ValueListenableBuilder<bool>(
              valueListenable: _homeStressReveal,
              builder: (context, revealStress, _) => HomeScreen(
                rightNowKey: _homeRightNowKey,
                vitalsKey: _homeVitalsKey,
                circleKey: _homeCircleKey,
                yourDayKey: _homeYourDayKey,
                insightsKey: _homeInsightsKey,
                isActive: isActive,
                openMoodCheckIn: widget.openMoodCheckIn,
                onScanTap: _openScan,
                onFitnessTap: () => _selectTab(3),
                onMyDayTap: () => _selectTab(1),
                revealStress: revealStress,
              ),
            ),
            1 => MyDayScreen(
              actionsKey: _myDayActionsKey,
              briefKey: _myDayBriefKey,
              nowKey: _myDayNowKey,
              prioritiesKey: _myDayPrioritiesKey,
              timelineKey: _myDayTimelineKey,
              tomorrowKey: _myDayTomorrowKey,
            ),
            2 => ScanScreen(
              isActive: isActive,
              onBackToHome: () => _selectTab(0),
              helpKey: _scanHelpKey,
              startKey: _scanStartKey,
              howItWorksKey: _scanHowKey,
            ),
            3 => FitnessScreen(
              isActive: isActive,
              actionsKey: _fitnessActionsKey,
              ringsKey: _fitnessRingsKey,
              buttonsKey: _fitnessButtonsKey,
              weekKey: _fitnessWeekKey,
              recentKey: _fitnessRecentKey,
              bodyKey: _fitnessBodyKey,
            ),
            4 => DashboardScreen(
              isActive: isActive,
              onScanTap: _openScan,
              customizeKey: _metricsCustomizeKey,
              physicalHealthKey: _metricsPhysicalKey,
              keyMetricsKey: _metricsKeyMetricsKey,
              insightsKey: _metricsInsightsKey,
            ),
            _ => const SizedBox.shrink(),
          };
          return TickerMode(enabled: isActive, child: page);
        },
      ),
    );
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
    if (index == _selectedIndex) return;
    final previousIndex = _selectedIndex;
    _logScreenView(index);
    _tabActivity[previousIndex].value = false;
    _tabActivity[index].value = !_chatOpen && !_detailRouteOpen;
    setState(() {
      _loadedTabs.add(index);
      _selectedIndex = index;
    });
    _insights.select(_contentNavigatorObserver.topRoute, _screenNames[index]);
    if (!_startupSplashMounted) _maybeStartTour(_screenNames[index]);
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
        if (mounted) {
          _homeStressReveal.value = true;
          setState(() => _startupSplashMounted = false);
          _maybeStartTour(_screenNames[_selectedIndex]);
        }
      }),
    );
  }

  /// Opens Panda chat, growing it out of [from] (the robot button that was
  /// tapped) or, when opened another way, out of the button's usual corner.
  /// Vivordo AI as a sheet over the current screen, about [insight].
  void _askAbout(ScreenInsight? insight) {
    _contextPrompt.value = insight;
    _openChat(sheet: true);
  }

  void _openChat({BuildContext? from, bool sheet = false}) {
    if (_chatOpen) return;
    final bubbleBox = from?.findRenderObject() as RenderBox?;
    final origin = bubbleBox == null
        ? Offset(
            MediaQuery.sizeOf(context).width - 64,
            MediaQuery.sizeOf(context).height - 150,
          )
        : bubbleBox.localToGlobal(bubbleBox.size.center(Offset.zero));
    _tabActivity[_selectedIndex].value = false;
    setState(() {
      _chatRevealOrigin = origin;
      _chatSheet.value = sheet;
      _pandaHasBeenOpened = true;
      _chatOpen = true;
    });
    _logScreenView(5);
    _chatRevealController.forward(from: 0);
  }

  /// A source chip or chart in Vivordo AI: close the chat and show where
  /// that data lives.
  Future<void> _openFromAssistant(String screen) async {
    await _closeChat();
    if (!mounted) return;
    final detail = switch (screen) {
      'sleep' => const SleepDetailScreen(),
      'heart' => const HeartRateDetailScreen(),
      'stress' => const StressDetailScreen(),
      'mood' => const MoodDetailScreen(),
      'physical_health' => const PhysicalHealthScreen(),
      _ => null,
    };
    if (detail != null) {
      _contentNavigatorKey.currentState?.push(
        MaterialPageRoute<void>(builder: (_) => detail),
      );
      return;
    }
    _selectTab(switch (screen) {
      'my_day' => 1,
      'fitness' || 'body' => 3,
      _ => 4,
    });
  }

  Future<void> _closeChat() async {
    if (!_chatOpen) return;
    await _chatRevealController.reverse();
    if (mounted) {
      setState(() => _chatOpen = false);
      _tabActivity[_selectedIndex].value = !_detailRouteOpen;
    }
  }

  void _handleContentNavigationChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final detailOpen = _contentNavigatorKey.currentState?.canPop() ?? false;
      _tabActivity[_selectedIndex].value = !detailOpen && !_chatOpen;
      _insights.select(
        _contentNavigatorObserver.topRoute,
        _screenNames[_selectedIndex],
      );
      if (detailOpen != _detailRouteOpen) {
        setState(() => _detailRouteOpen = detailOpen);
      }
    });
  }

  void _logScreenView(int index) {
    if (index >= 0 && index < _screenNames.length) {
      AnalyticsService().logScreenView(_screenNames[index]);
    }
  }

  void _openScan() => _selectTab(2);

  @override
  Widget build(BuildContext context) {
    final detailRouteVisible = _detailRouteOpen;
    // Read here, above the Scaffold: its body sees a zero bottom inset
    // because the Scaffold already resizes for the keyboard.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    // The assistant would otherwise sit on top of text fields' send buttons.
    // During the tour the robot has left its button; it is back for the
    // final step, which points at it.
    final hideAssistant =
        _chatOpen || keyboardOpen || (_tourScreen != null && !_tourShowsChat);
    final activePage = IndexedStack(
      index: _selectedIndex,
      children: List.generate(
        _tabPages.length,
        (index) => _loadedTabs.contains(index)
            ? _tabPages[index]
            : const SizedBox.shrink(),
      ),
    );
    final contentNavigator = Navigator(
      key: _contentNavigatorKey,
      observers: [_contentNavigatorObserver],
      pages: [
        MaterialPage<void>(
          name: 'main-tabs',
          key: const ValueKey('main-content-tabs'),
          child: activePage,
        ),
      ],
      onDidRemovePage: (_) {},
    );

    return PopScope(
      canPop: !_chatOpen && !detailRouteVisible,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_chatOpen) {
          _closeChat();
        } else if (detailRouteVisible) {
          _contentNavigatorKey.currentState?.maybePop(result);
        }
      },
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: ScreenInsightScope(
                  controller: _insights,
                  child: contentNavigator,
                ),
              ),
            ),
            if (!detailRouteVisible)
              Positioned(
                bottom: 30,
                left: 24,
                right: 24,
                child: _buildFloatingNavBar(),
              ),
            Positioned(
              key: const ValueKey('ai-chat-bubble-layer'),
              right: 30,
              left: 20,
              bottom: detailRouteVisible ? 30 : 116,
              child: IgnorePointer(
                key: _chatLayerKey,
                ignoring: hideAssistant,
                child: AnimatedOpacity(
                  opacity: hideAssistant ? 0 : 1,
                  duration: const Duration(milliseconds: 140),
                  child: AnimatedBuilder(
                    animation: Listenable.merge([
                      _insights,
                      FitnessWorkoutTimerState.isRunning,
                    ]),
                    builder: (context, _) => ContextualInsightBar(
                      insight: _insights.current,
                      suppressed:
                          hideAssistant ||
                          FitnessWorkoutTimerState.isRunning.value,
                      collapsed: _buildChatBubble(),
                      onAsk: (_) => _askAbout(_insights.current),
                    ),
                  ),
                ),
              ),
            ),
            if (_pandaHasBeenOpened && _chatOpen && _chatSheet.value)
              Positioned.fill(
                child: GestureDetector(
                  onTap: _closeChat,
                  child: FadeTransition(
                    opacity: _chatRevealAnimation,
                    child: const ColoredBox(color: Colors.black38),
                  ),
                ),
              ),
            if (_pandaHasBeenOpened)
              AnimatedPositioned(
                key: const ValueKey('persistent-ai-chat-layer'),
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                left: 0,
                right: 0,
                bottom: 0,
                top: _chatSheet.value
                    ? MediaQuery.sizeOf(context).height * .24
                    : 0,
                child: TickerMode(
                  enabled: _chatOpen,
                  child: IgnorePointer(
                    ignoring: !_chatOpen,
                    child: AnimatedBuilder(
                      animation: _chatRevealAnimation,
                      // Reuse one mounted chat instance so closing never
                      // resets the current conversation. Sheet or full, the
                      // widgets above it stay the same, or its state is lost.
                      child: _persistentChatScreen,
                      builder: (context, child) => FractionalTranslation(
                        translation: Offset(
                          0,
                          _chatSheet.value ? 1 - _chatRevealAnimation.value : 0,
                        ),
                        child: ClipPath(
                          clipper: _chatSheet.value
                              ? const _SheetClipper()
                              : _CircularRevealClipper(
                                  origin: _chatRevealOrigin,
                                  progress: _chatRevealAnimation.value,
                                ),
                          child: child,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (_tourScreen != null)
              Positioned.fill(
                child: AppTour(
                  key: ValueKey('tour-$_tourScreen'),
                  steps: _tourScripts[_tourScreen]!,
                  onSelectTab: _selectTab,
                  onFinished: _finishTour,
                  onStepChanged: (step) => setState(
                    () => _tourShowsChat =
                        _tourScripts[_tourScreen]![step].target ==
                        _chatLayerKey,
                  ),
                  home: _chatLayerKey,
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

  // No GlobalKey here: the insight bar crossfades this button, so two copies
  // can briefly coexist, which a GlobalKey forbids.
  Widget _buildChatBubble() => Material(
    color: primaryPurple,
    elevation: 10,
    shadowColor: primaryPurple.withValues(alpha: .38),
    shape: const CircleBorder(),
    clipBehavior: Clip.antiAlias,
    child: Builder(
      builder: (bubbleContext) => InkWell(
        onTap: () => _openChat(from: bubbleContext),
        child: const SizedBox(
          width: 64,
          height: 64,
          child: Center(child: VivordoRobot(size: 30, faceOnly: true)),
        ),
      ),
    ),
  );

  Widget _buildFloatingNavBar() {
    final colors = context.vivordoColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_cachedGlassSettingsIsDark != isDark) {
      _cachedGlassSettingsIsDark = isDark;
      _cachedGlassSettings = LiquidGlassSettings(
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
    }
    final glassSettings = _cachedGlassSettings!;

    return RepaintBoundary(
      key: _navBarKey,
      child: DecoratedBox(
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
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
      ),
    );
  }

  Widget _navItem(IconData icon, String label, int index) {
    bool isActive = _selectedIndex == index;
    final isWorkoutPulse =
        index == 3 && FitnessWorkoutTimerState.isRunning.value;
    return InkWell(
      onTap: () {
        // The standard iOS selection tick, only when the tab actually changes.
        if (index != _selectedIndex) unawaited(HapticFeedback.selectionClick());
        _selectTab(index);
      },
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
              // Without this boundary the pulse repaints the whole liquid
              // glass nav bar every frame.
              RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _fitnessPulseController,
                  child: Icon(
                    icon,
                    color: isActive ? Colors.white : primaryPurple,
                    size: 23,
                  ),
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
                        child: child,
                      ),
                    );
                  },
                ),
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

class _ContentNavigatorObserver extends NavigatorObserver {
  _ContentNavigatorObserver(this.onChanged);

  final VoidCallback onChanged;
  final List<Route<dynamic>> _routes = [];
  Route<dynamic>? get topRoute => _routes.lastOrNull;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
    onChanged();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    onChanged();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    onChanged();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (index >= 0) {
      if (newRoute == null) {
        _routes.removeAt(index);
      } else {
        _routes[index] = newRoute;
      }
    }
    onChanged();
  }
}

class _SheetClipper extends CustomClipper<Path> {
  const _SheetClipper();

  @override
  Path getClip(Size size) => Path()
    ..addRRect(
      RRect.fromRectAndCorners(
        Offset.zero & size,
        topLeft: const Radius.circular(28),
        topRight: const Radius.circular(28),
      ),
    );

  @override
  bool shouldReclip(_SheetClipper oldClipper) => false;
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
