import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vivordo_health/firebase_options.dart';
import 'package:vivordo_health/screens/main_navigation.dart';
import 'package:vivordo_health/src/services/notification_service.dart';
import 'package:vivordo_health/src/services/achievement_unlock_service.dart';
import 'package:vivordo_health/src/services/home_widget_service.dart';
import 'package:vivordo_health/src/services/workout_live_activity_service.dart';
import 'package:vivordo_health/src/services/health_service.dart';
import 'package:vivordo_health/src/services/fitbit_service.dart';
import 'package:vivordo_health/src/services/whoop_service.dart';
import 'package:vivordo_health/src/services/analytics_service.dart';
import 'package:vivordo_health/src/services/stress_score_service.dart';
import 'package:vivordo_health/src/services/version_gate_service.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';
import 'package:vivordo_health/widgets/achievement_unlocked_dialog.dart';
import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/email_verification_screen.dart';
import 'screens/force_update_screen.dart';
import 'screens/circle_screen.dart';
import 'screens/fitness_screen.dart';
import 'screens/wellness_detail_screen.dart';
import 'screens/whats_new_screen.dart';

// Change this identifier whenever a new release should display a fresh
// What's New screen. It is stored per user in Firestore.
const _whatsNewReleaseId = 'major_refresh_2026_08';

// Global navigator key for notification navigation
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Uncomment to route Cloud Function calls to the local emulator instead of
  // the deployed function. Requires `firebase emulators:start --only functions`.
  // if (kDebugMode) {
  //   FirebaseFunctions.instance.useFunctionsEmulator('localhost', 5001);
  // }

  // Initialize notification service
  await NotificationService().initialize();
  if (FirebaseAuth.instance.currentUser == null) {
    await NotificationService().clearUserReminders();
  }

  runApp(
    // Only one provider: the auth state stream.
    // UserModel data is loaded per-screen (profile) or via HealthService
    // (consent). A second StreamProvider<UserModel?> reading User? at creation
    // time always got null (initialData) and created a broken/wasted Firestore
    // listener — removed to reduce concurrent listener count.
    MultiProvider(
      providers: [
        StreamProvider<User?>(
          // userChanges() (not authStateChanges()) — it's the one Firebase
          // guarantees re-emits after currentUser.reload(), which is how
          // EmailVerificationScreen picks up a newly-verified email.
          // authStateChanges() only fires on sign-in/out, so AuthGate would
          // keep reading a stale, still-unverified User forever after
          // verification, even though reload() elsewhere already saw it flip.
          create: (_) => FirebaseAuth.instance.userChanges(),
          // Seed the provider from Firebase's restored session so an already
          // signed-in user does not briefly see LoginScreen while waiting for
          // the first stream event.
          initialData: FirebaseAuth.instance.currentUser,
        ),
        ChangeNotifierProxyProvider<User?, ThemeController>(
          create: (_) => ThemeController(),
          update: (_, user, controller) =>
              (controller ?? ThemeController())..bindUser(user),
        ),
      ],
      // VersionGate checks Remote Config before anything else renders, then
      // falls through to MyApp — kept as the provider's child (not wrapping
      // the providers) so VersionGate's descendants still have User?/
      // ThemeController available via context.
      child: const VersionGate(),
    ),
  );
}

/// Checks the installed app version against Remote Config exactly once per
/// app launch, before any real screen (including LoginScreen) is reachable.
/// Deliberately NOT built as part of the '/' route inside MyApp — AuthGate
/// is reached via pushNamedAndRemoveUntil('/', ...) repeatedly during normal
/// use (after login, signup, email verification), and re-running this check
/// on every one of those would flash a loading spinner each time.
class VersionGate extends StatefulWidget {
  const VersionGate({super.key});

  @override
  State<VersionGate> createState() => _VersionGateState();
}

class _VersionGateState extends State<VersionGate> {
  late final Future<VersionCheckResult> _future;

  @override
  void initState() {
    super.initState();
    _future = VersionGateService.check();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<VersionCheckResult>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(body: Center(child: CircularProgressIndicator())),
          );
        }
        final result = snapshot.data;
        if (result != null && result.updateRequired) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            home: ForceUpdateScreen(updateUrl: result.updateUrl),
          );
        }
        return const MyApp();
      },
    );
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _openingWorkout = false;
  bool _openingWidget = false;
  StreamSubscription<AchievementUnlock>? _achievementUnlockSubscription;
  final List<AchievementUnlock> _pendingAchievementUnlocks = [];
  bool _showingAchievementUnlock = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WorkoutLiveActivityService.configureLaunchHandler(_openActiveWorkout);
      HomeWidgetService.configureLaunchHandler(_openWidgetDestination);
    });
    _achievementUnlockSubscription = AchievementUnlockService.unlocks.listen(
      _queueAchievementUnlock,
    );
  }

  void _queueAchievementUnlock(AchievementUnlock achievement) {
    _pendingAchievementUnlocks.add(achievement);
    unawaited(_showNextAchievementUnlock());
  }

  Future<void> _showNextAchievementUnlock() async {
    if (_showingAchievementUnlock || _pendingAchievementUnlocks.isEmpty) return;
    final navigatorContext = navigatorKey.currentContext;
    if (navigatorContext == null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(_showNextAchievementUnlock()),
      );
      return;
    }
    _showingAchievementUnlock = true;
    final achievement = _pendingAchievementUnlocks.removeAt(0);
    await showGeneralDialog<void>(
      context: navigatorContext,
      barrierDismissible: false,
      barrierLabel: 'Achievement unlocked',
      barrierColor: Colors.black.withValues(alpha: .82),
      transitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (dialogContext, animation, secondaryAnimation) =>
          AchievementUnlockedDialog(
            achievement: achievement,
            onDismiss: () => Navigator.of(dialogContext).pop(),
          ),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(scale: curved, child: child),
        );
      },
    );
    _showingAchievementUnlock = false;
    if (_pendingAchievementUnlocks.isNotEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 180));
      unawaited(_showNextAchievementUnlock());
    }
  }

  Future<void> _openWidgetDestination(String destination) async {
    if (_openingWidget || FirebaseAuth.instance.currentUser == null) return;
    if (!const {
      'home',
      'wellness',
      'fitness',
      'calendar',
    }.contains(destination)) {
      return;
    }
    _openingWidget = true;
    try {
      NavigatorState? navigator;
      for (var attempt = 0; attempt < 20 && navigator == null; attempt++) {
        navigator = navigatorKey.currentState;
        if (navigator == null) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
      if (navigator == null || !mounted) return;

      if (destination == 'fitness') {
        navigator.pushNamedAndRemoveUntil('/fitness', (_) => false);
        return;
      }

      if (destination == 'calendar') {
        navigator.pushNamedAndRemoveUntil('/calendar', (_) => false);
        return;
      }

      navigator.pushNamedAndRemoveUntil('/home', (_) => false);
      if (destination == 'wellness') {
        await WidgetsBinding.instance.endOfFrame;
        if (mounted) unawaited(navigator.pushNamed('/wellness'));
      }
    } finally {
      _openingWidget = false;
    }
  }

  Future<void> _openActiveWorkout() async {
    if (_openingWorkout) return;
    _openingWorkout = true;
    try {
      if (FirebaseAuth.instance.currentUser == null) return;
      final hasWorkout = await prepareActiveWorkoutForLaunch();
      if (!hasWorkout) return;

      NavigatorState? navigator;
      for (var attempt = 0; attempt < 20 && navigator == null; attempt++) {
        navigator = navigatorKey.currentState;
        if (navigator == null) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
      if (navigator == null || !mounted) return;
      await navigator.pushNamed('/active-workout');
    } finally {
      _openingWorkout = false;
    }
  }

  @override
  void dispose() {
    WorkoutLiveActivityService.clearLaunchHandler();
    HomeWidgetService.clearLaunchHandler();
    _achievementUnlockSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeController = context.watch<ThemeController>();
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Vivordo Health',
      debugShowCheckedModeBanner: false,
      builder: (context, child) => Actions(
        actions: {
          EditableTextTapOutsideIntent:
              CallbackAction<EditableTextTapOutsideIntent>(
                onInvoke: (_) {
                  FocusManager.instance.primaryFocus?.unfocus();
                  return null;
                },
              ),
        },
        child: child ?? const SizedBox.shrink(),
      ),
      theme: VivordoTheme.light,
      darkTheme: VivordoTheme.dark,
      themeMode: themeController.mode,
      initialRoute: '/',
      routes: {
        '/': (context) => const AuthGate(),
        '/signup': (context) => const SignupScreen(),
        '/home': (context) => const MainNavigationScreen(),
        '/calendar': (context) => const MainNavigationScreen(initialIndex: 1),
        '/fitness': (context) => const MainNavigationScreen(initialIndex: 3),
        '/wellness': (context) => const WellnessDetailScreen(),
        '/scan': (context) => const MainNavigationScreen(initialIndex: 2),
        '/ai-chat': (context) => const MainNavigationScreen(initialIndex: 5),
        '/circle': (context) => const CircleScreen(),
        '/active-workout': (context) => const ActiveWorkoutScreen(),
      },
    );
  }
}

/// AuthGate watches the auth state and routes accordingly.
/// On login it triggers a full 30-day HealthKit sync.
/// While logged in it syncs today's data every 3 minutes.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  String? _lastSyncedUid;
  Timer? _syncTimer;
  // Cached by uid so userChanges() firing more often than authStateChanges()
  // used to (token refresh, any profile update anywhere in the app) doesn't
  // re-run this Firestore read on every emission — only when the signed-in
  // user actually changes.
  String? _userDocUid;
  Future<DocumentSnapshot>? _userDocFuture;
  String? _locallyDismissedWhatsNewUid;

  void _dismissWhatsNew(String uid) {
    if (!mounted) return;
    setState(() => _locallyDismissedWhatsNewUid = uid);
    unawaited(_persistWhatsNewSeen(uid));
  }

  Future<void> _persistWhatsNewSeen(String uid) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'preferences.whatsNewSeenRelease': _whatsNewReleaseId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (error) {
      debugPrint('Unable to persist What\'s New state: $error');
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Sync HealthKit data every 3 minutes while the app is open, then retry
    // the stress score. computeAndSave() is otherwise only triggered from
    // HomeScreen.initState(), which only reruns when the user navigates
    // back to the Home tab — if the one attempt on app open fails (BaaS
    // cold start, network blip), nothing else ever retries it. This timer
    // is what makes the score keep trying in the background, same as any
    // other continuously-tracked metric, instead of getting stuck on
    // whatever the first attempt of the day happened to return.
    _syncTimer = Timer.periodic(const Duration(minutes: 3), (_) async {
      if (FirebaseAuth.instance.currentUser != null) {
        await HealthService().syncToday();
        await FitbitService.instance.syncInBackground();
        await WhoopService.instance.syncInBackground();
        StressScoreService.computeAndSave().catchError((_) {});
      }
    });
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Sync today's data whenever the app comes back to the foreground, and
  /// track foreground time as analytics sessions (resume opens a session,
  /// backgrounding closes it and records its duration).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (FirebaseAuth.instance.currentUser != null) {
        HealthService().syncToday().whenComplete(() async {
          await FitbitService.instance.syncInBackground();
          await WhoopService.instance.syncInBackground();
        });
        unawaited(HomeWidgetService.refreshCalendarSnapshot());
        AnalyticsService().startSession();
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      AnalyticsService().endSession();
    }
  }

  /// Full 30-day sync triggered once per login session. Also the point where we
  /// record the login and open the first analytics session for it.
  void _triggerFullSync(String uid) {
    if (_lastSyncedUid == uid) return;
    _lastSyncedUid = uid;
    HealthService().syncToFirestore(daysBack: 30).whenComplete(() async {
      await FitbitService.instance.syncInBackground(daysBack: 30);
      await WhoopService.instance.syncInBackground(daysBack: 30);
    });
    NotificationService().configureForUser(uid);
    unawaited(HomeWidgetService.refreshCalendarSnapshot(force: true));
    AnalyticsService().logLogin();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<User?>();

    if (user == null) {
      if (_lastSyncedUid != null) {
        NotificationService().clearUserReminders();
      }
      _lastSyncedUid = null;
      _userDocUid = null;
      _userDocFuture = null;
      _locallyDismissedWhatsNewUid = null;
      // Clear the cached consent broadcast so the next login gets a fresh stream
      HealthService().clearConsentCache();
      return const LoginScreen();
    }

    // Blocks app access until the user has clicked the link in their
    // verification email. This is what actually prevents an account being
    // created and used with an address that doesn't exist — Firebase can't
    // check deliverability at signup, only that a real inbox opened the link.
    if (!user.emailVerified) {
      return const EmailVerificationScreen();
    }

    _triggerFullSync(user.uid);

    if (_userDocUid != user.uid) {
      _userDocUid = user.uid;
      _userDocFuture = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
    }

    return FutureBuilder<DocumentSnapshot>(
      future: _userDocFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return const MainNavigationScreen();
        }

        final data = snapshot.data?.data() as Map<String, dynamic>?;
        final preferences = data?['preferences'] as Map<String, dynamic>?;
        final onboardingSeen = preferences?['onboardingSeen'] == true;
        final onboardingCompleted = data?['onboardingCompleted'] == true;

        // The signup questionnaire records `onboardingCompleted`, while the
        // lightweight introductory carousel records `onboardingSeen`. Either
        // means the user has already completed an onboarding path.
        if (onboardingSeen || onboardingCompleted) {
          final seenRelease = preferences?['whatsNewSeenRelease'] as String?;
          final dismissedLocally = _locallyDismissedWhatsNewUid == user.uid;
          if (!dismissedLocally && seenRelease != _whatsNewReleaseId) {
            return WhatsNewScreen(onDismiss: () => _dismissWhatsNew(user.uid));
          }
          return const MainNavigationScreen();
        }

        return OnboardingScreen(
          onFinished: () async {
            await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .set({
                  'preferences.onboardingSeen': true,
                  'onboardingCompleted': true,
                  'onboardingCompletedAt': FieldValue.serverTimestamp(),
                  'updatedAt': FieldValue.serverTimestamp(),
                }, SetOptions(merge: true));

            // New users have just seen onboarding for this release, so do not
            // immediately follow it with an update recap on their next launch.
            await _persistWhatsNewSeen(user.uid);

            if (!context.mounted) return;

            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const MainNavigationScreen()),
            );
          },
        );
      },
    );
  }
}
