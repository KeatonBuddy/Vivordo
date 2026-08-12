import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vivordo_health/firebase_options.dart';
import 'package:vivordo_health/screens/main_navigation.dart';
import 'package:vivordo_health/src/services/notification_service.dart';
import 'package:vivordo_health/src/services/health_service.dart';
import 'package:vivordo_health/src/services/analytics_service.dart';
import 'package:vivordo_health/src/services/stress_score_service.dart';
import 'package:vivordo_health/src/services/version_gate_service.dart';
import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/email_verification_screen.dart';
import 'screens/force_update_screen.dart';

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
    StreamProvider<User?>(
      // userChanges() (not authStateChanges()) — it's the one Firebase
      // guarantees re-emits after currentUser.reload(), which is how
      // EmailVerificationScreen picks up a newly-verified email.
      // authStateChanges() only fires on sign-in/out, so AuthGate would
      // keep reading a stale, still-unverified User forever after
      // verification, even though reload() elsewhere already saw it flip.
      create: (_) => FirebaseAuth.instance.userChanges(),
      initialData: null,
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

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Vivordo Health',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'DMSans',
        primaryColor: const Color(0xFF857DEA),
        scaffoldBackgroundColor: const Color(0xFFFBFaff),
        colorScheme: ColorScheme.fromSwatch().copyWith(
          primary: const Color(0xFF857DEA),
          secondary: const Color(0xFF857DEA),
        ),
        useMaterial3: true,
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const AuthGate(),
        '/signup': (context) => const SignupScreen(),
        '/home': (context) => const MainNavigationScreen(),
        '/scan': (context) => const MainNavigationScreen(initialIndex: 1),
        '/ai-chat': (context) => const MainNavigationScreen(initialIndex: 3),
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
        HealthService().syncToday();
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
    HealthService().syncToFirestore(daysBack: 30);
    NotificationService().configureForUser(uid);
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
      _userDocFuture =
          FirebaseFirestore.instance.collection('users').doc(user.uid).get();
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

        if (onboardingSeen) {
          return const MainNavigationScreen();
        }

        return OnboardingScreen(
          onFinished: () async {
            await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .update({
                  'preferences.onboardingSeen': true,
                  'updatedAt': FieldValue.serverTimestamp(),
                });

            if (!mounted) return;

            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const MainNavigationScreen()),
            );
          },
        );
      },
    );
  }
}
