import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';

import '../src/services/ai_consent.dart';
import '../src/services/calendar_service.dart';
import '../src/services/fitbit_service.dart';
import '../src/services/health_service.dart';
import '../src/services/notification_service.dart';
import '../src/services/outlook_calendar_service.dart';
import '../src/services/personal_profile_service.dart';
import '../src/services/user_service.dart';
import '../src/services/whoop_service.dart';
import '../src/utils/day_wrap_up.dart';
import '../src/utils/sleep_schedule.dart';
import '../widgets/apple_ui.dart';
import '../widgets/birth_year_picker.dart';
import '../widgets/privacy_support_links.dart';
import '../widgets/sleep_schedule_editor.dart';
import 'personal_profile_screen.dart' show MeasurementEditorSheet;

/// The onboarding everyone completes once. Bump it to send everyone through
/// onboarding again.
const kOnboardingVersion = 2;

/// Whether this user document still needs [OnboardingFlowScreen].
bool needsOnboarding(Map<String, dynamic>? userDoc) =>
    ((userDoc?['onboardingVersion'] as num?) ?? 0) < kOnboardingVersion;

enum OnboardingStep {
  intro,
  about,
  wrapUp,
  health,
  sleep,
  wearables,
  calendar,
  ai,
  notifications,
}

/// The steps for this user: people who finished the old onboarding see a
/// "what's changed" intro first.
List<OnboardingStep> onboardingSteps(Map<String, dynamic>? userDoc) => [
  if (userDoc?['onboardingCompleted'] == true) OnboardingStep.intro,
  ...OnboardingStep.values.where((step) => step != OnboardingStep.intro),
];

const _purple = VivordoTheme.brand;
const _page = Color(0xFFF2F2F7);
const _ink = Color(0xFF1C1C1E);
const _grey = Color(0xFF8E8E93);
const _line = Color(0xFFE5E5EA);

/// Shown by AuthGate after sign-in until [kOnboardingVersion] is saved
/// (docs: the onboarding-redesign idea). Every answer saves as its step is
/// completed, so quitting halfway loses nothing; answers already saved are
/// filled in.
class OnboardingFlowScreen extends StatefulWidget {
  const OnboardingFlowScreen({
    super.key,
    required this.userDoc,
    required this.onFinished,
  });

  final Map<String, dynamic>? userDoc;
  final Future<void> Function() onFinished;

  @override
  State<OnboardingFlowScreen> createState() => _OnboardingFlowScreenState();
}

class _OnboardingFlowScreenState extends State<OnboardingFlowScreen> {
  final _pages = PageController();
  late final List<OnboardingStep> _steps = onboardingSteps(widget.userDoc);
  int _index = 0;
  bool _busy = false;

  // The sign-in profile's name is the one the app shows (Home's greeting).
  late final _name = TextEditingController(
    text:
        FirebaseAuth.instance.currentUser?.displayName ??
        (widget.userDoc?['displayName'] as String?) ??
        '',
  );
  late PersonalProfile _profile = PersonalProfile.fromUserData(widget.userDoc);
  late int? _birthYear = _profile.birthYear;
  late String? _sex = _profile.sex;

  late int _wrapUp = _savedWrapUp ?? kDefaultDayWrapUpMinutes;
  late bool _wrapUpVaries =
      _preferences.containsKey('dayWrapUpMinutes') && _savedWrapUp == null;

  late SleepSchedule _sleep =
      SleepSchedule.fromPreferences(_preferences) ?? SleepSchedule.fallback;

  /// Whether [_sleep] was filled in from tracked sleep.
  bool _sleepFromHealth = false;

  late bool _healthConnected =
      (widget.userDoc?['healthKitConsent'] as Map?)?.values.contains(true) ==
      true;
  late bool _whoop = widget.userDoc?['whoopConnected'] == true;
  late bool _fitbit = widget.userDoc?['fitbitConnected'] == true;
  bool _google = false;
  bool _outlook = false;
  bool _aiOn = false;

  Map<String, dynamic> get _preferences =>
      (widget.userDoc?['preferences'] as Map?)?.cast<String, dynamic>() ??
      const {};
  int? get _savedWrapUp => (_preferences['dayWrapUpMinutes'] as num?)?.toInt();
  String get _uid => FirebaseAuth.instance.currentUser!.uid;
  DocumentReference<Map<String, dynamic>> get _userRef =>
      FirebaseFirestore.instance.collection('users').doc(_uid);

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
    unawaited(_loadConnections());
    if (_healthConnected) unawaited(_prefillSleep());
  }

  /// Fills the sleep step from the last two weeks of tracked sleep, unless
  /// a schedule is already saved or the times were already changed.
  Future<void> _prefillSleep() async {
    if (SleepSchedule.fromPreferences(_preferences) != null) return;
    try {
      final tracked = SleepSchedule.fromNights(
        await HealthService().recentSleepNights(),
      );
      if (tracked == null ||
          !mounted ||
          !identical(_sleep, SleepSchedule.fallback)) {
        return;
      }
      setState(() {
        _sleep = tracked;
        _sleepFromHealth = true;
      });
    } catch (error) {
      debugPrint('Sleep schedule prefill failed: $error');
    }
  }

  Future<void> _loadConnections() async {
    final results = await Future.wait([
      CalendarService.hasCalendarAccess(),
      OutlookCalendarService.isSignedIn(),
      AiConsent.granted(_uid),
    ]);
    if (!mounted) return;
    setState(() {
      _google = results[0];
      _outlook = results[1];
      _aiOn = results[2];
    });
  }

  @override
  void dispose() {
    _pages.dispose();
    _name.dispose();
    super.dispose();
  }

  /// Runs [save] (if any) with a spinner, then moves on; a failed save
  /// stays on the step.
  Future<void> _next([Future<void> Function()? save]) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await save?.call();
      if (_index == _steps.length - 1) {
        await _userRef.set({
          'onboardingVersion': kOnboardingVersion,
          'onboardingCompleted': true,
          'onboardingCompletedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        await widget.onFinished();
        return;
      }
      await _pages.nextPage(
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    } catch (error) {
      debugPrint('Onboarding step failed: $error');
      if (mounted) {
        showToast(
          context,
          "Couldn't save. Check your connection and try again.",
          kind: ToastKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Runs a connect action; [onError] words its failure.
  Future<void> _connect(
    Future<void> Function() action, {
    String onError = "Couldn't connect. You can try again in Settings.",
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      debugPrint('Onboarding connect failed: $error');
      if (mounted) {
        showToast(context, onError, kind: ToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  DateTime get _weekStart {
    final today = DateTime.now();
    return DateTime(today.year, today.month, today.day - (today.weekday - 1));
  }

  // Onboarding is always light, so pickers and the status bar follow it even
  // when the phone is in dark mode.
  @override
  Widget build(BuildContext context) => onboardingLight(
    Scaffold(
      backgroundColor: _page,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 4),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: _index == 0 || _busy
                        ? null
                        : () => _pages.previousPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOutCubic,
                          ),
                    icon: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 18,
                      color: _index == 0 ? Colors.transparent : _ink,
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        for (var i = 0; i < _steps.length; i++)
                          Expanded(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              height: 4,
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              decoration: BoxDecoration(
                                color: i <= _index ? _purple : _line,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pages,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _index = i),
                children: [for (final step in _steps) _stepPage(step)],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _stepPage(OnboardingStep step) => switch (step) {
    OnboardingStep.intro => _StepLayout(
      kicker: 'WELCOME BACK',
      title: 'Vivordo has changed a lot',
      body:
          'The new scores need a few details and permissions. It takes about '
          'a minute, and anything you already told us is filled in.',
      primary: 'Continue',
      onPrimary: _busy ? null : () => _next(),
      children: const [
        _Bullet(Icons.bolt_rounded, 'Capacity', 'the energy you have today'),
        _Bullet(
          Icons.event_note_rounded,
          'Your Day',
          "what's ahead and what it took",
        ),
        _Bullet(
          Icons.directions_run_rounded,
          'Physical Health',
          'your fitness and habits',
        ),
        _Bullet(
          Icons.warning_amber_rounded,
          'Burnout check',
          'an early warning when things pile up',
        ),
      ],
    ),
    OnboardingStep.about => _StepLayout(
      kicker: 'ABOUT YOU',
      title: 'A bit about you',
      body: 'Physical Health compares your fitness with people your age.',
      primary: 'Continue',
      onPrimary:
          _busy ||
              _name.text.trim().isEmpty ||
              _birthYear == null ||
              _sex == null
          ? null
          : () => _next(_saveAbout),
      children: [
        _Card(
          children: [
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'First name',
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const Divider(height: 1, color: _line),
            _Row(
              label: 'Year of birth',
              value: _birthYear?.toString(),
              onTap: () async {
                final year = await showBirthYearPicker(
                  context,
                  initial: _birthYear,
                );
                if (year != null) setState(() => _birthYear = year);
              },
            ),
            const Divider(height: 1, color: _line),
            _Row(
              label: 'Height and weight',
              value: _profile.heightCm == null || _profile.weightKg == null
                  ? null
                  : '${_feetInches(_profile.heightCm!)} · '
                        '${(_profile.weightKg! * 2.2046226218).round()} lbs',
              placeholder: 'Add',
              onTap: _editMeasurements,
            ),
          ],
        ),
        const SizedBox(height: 14),
        const Text('Sex', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        AppSegmented<String>(
          segments: {
            for (final sex in profileSexes) sex: profileSexLabels[sex]!,
          },
          value: _sex,
          onChanged: (sex) => setState(() => _sex = sex),
        ),
        const SizedBox(height: 10),
        const Text(
          'Height and weight are optional, and sharpen the cardio fitness '
          'estimate. You can change any of this later in your profile.',
          style: TextStyle(fontSize: 12, color: _grey),
        ),
      ],
    ),
    OnboardingStep.wrapUp => _StepLayout(
      kicker: 'YOUR DAY',
      title: 'When do you usually wrap up work or classes?',
      body: 'Anything after this counts as after hours in Your Day.',
      primary: 'Continue',
      onPrimary: _busy ? null : () => _next(_saveWrapUp),
      children: [
        AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: _wrapUpVaries ? .35 : 1,
          child: IgnorePointer(
            ignoring: _wrapUpVaries,
            child: SizedBox(
              height: 170,
              // Same wheel look as showVivordoTimePicker.
              child: CupertinoTheme(
                data: CupertinoThemeData(
                  brightness: Brightness.light,
                  primaryColor: const Color(0xFF6254F4),
                  textTheme: CupertinoTextThemeData(
                    dateTimePickerTextStyle: TextStyle(
                      color: context.vivordoColors.textPrimary,
                      fontSize: 22,
                    ),
                  ),
                ),
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.time,
                  minuteInterval: 15,
                  initialDateTime: DateTime(
                    2026,
                    1,
                    1,
                    _wrapUp ~/ 60,
                    _wrapUp % 60 - _wrapUp % 15,
                  ),
                  onDateTimeChanged: (time) =>
                      _wrapUp = time.hour * 60 + time.minute,
                ),
              ),
            ),
          ),
        ),
        _Card(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'It varies day to day',
                      style: TextStyle(fontSize: 15, color: _ink),
                    ),
                  ),
                  AppSwitch(
                    value: _wrapUpVaries,
                    onChanged: (value) => setState(() => _wrapUpVaries = value),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    ),
    OnboardingStep.sleep => _StepLayout(
      kicker: 'YOUR SLEEP',
      title: 'When do you usually sleep?',
      body:
          'Vivordo forecasts your energy through the day from this until it '
          'has a week of your tracked sleep. You can change it on the Sleep '
          'screen.',
      primary: 'Continue',
      onPrimary: _busy ? null : () => _next(() => saveSleepSchedule(_sleep)),
      children: [
        SleepScheduleEditor(
          schedule: _sleep,
          onChanged: (schedule) => setState(() => _sleep = schedule),
        ),
        if (_sleepFromHealth) ...[
          const SizedBox(height: 10),
          Text(
            'Filled in from your last two weeks in $_healthName.',
            style: const TextStyle(fontSize: 12, color: _grey),
          ),
        ],
      ],
    ),
    OnboardingStep.health => _StepLayout(
      icon: Icons.favorite_rounded,
      iconColor: const Color(0xFFE24B4A),
      kicker: 'CONNECT',
      title: 'Connect $_healthName',
      body:
          'Your scores come from this. Vivordo only reads your data; it never '
          'writes to $_healthName.',
      primary: _healthConnected ? 'Continue' : 'Connect $_healthName',
      onPrimary: _busy
          ? null
          : () => _next(_healthConnected ? null : _connectHealth),
      secondary: _healthConnected ? null : 'Not now',
      onSecondary: _busy ? null : () => _next(),
      children: [
        if (_healthConnected) const _Connected('Connected'),
        const _Bullet(
          Icons.bedtime_rounded,
          'Sleep',
          'Capacity and Physical Health',
        ),
        const _Bullet(
          Icons.monitor_heart_rounded,
          'Resting heart rate and HRV',
          'Capacity and the burnout check',
        ),
        const _Bullet(
          Icons.directions_walk_rounded,
          'Steps and exercise',
          'Effort and Physical Health',
        ),
        const _Bullet(Icons.air_rounded, 'Cardio fitness', 'Physical Health'),
      ],
    ),
    OnboardingStep.wearables => _StepLayout(
      kicker: 'CONNECT',
      title: 'Wear a WHOOP or Fitbit?',
      body: "Optional. Adds recovery data $_healthName doesn't have.",
      primary: 'Continue',
      onPrimary: _busy ? null : () => _next(),
      children: [
        _Card(
          children: [
            _Row(
              label: 'WHOOP',
              value: _whoop ? 'Connected' : null,
              placeholder: 'Connect',
              onTap: _whoop
                  ? null
                  : () => _connect(() async {
                      await WhoopService.instance.connect();
                      if (mounted) setState(() => _whoop = true);
                    }),
            ),
            const Divider(height: 1, color: _line),
            _Row(
              label: 'Fitbit',
              value: _fitbit ? 'Connected' : null,
              placeholder: 'Connect',
              onTap: _fitbit ? null : _connectFitbit,
            ),
            if (defaultTargetPlatform == TargetPlatform.iOS) ...[
              const Divider(height: 1, color: _line),
              const _Row(label: 'Apple Watch', value: 'Through Apple Health'),
            ],
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'No wearable? Your phone and morning check-ins still work.',
          style: TextStyle(fontSize: 12, color: _grey),
        ),
      ],
    ),
    OnboardingStep.calendar => _StepLayout(
      icon: Icons.calendar_month_rounded,
      iconColor: const Color(0xFF185FA5),
      kicker: 'CONNECT',
      title: 'Add your calendar',
      body:
          "Your Day uses your events' times and lengths to see what's ahead "
          'and spot back-to-backs.',
      primary: 'Continue',
      onPrimary: _busy ? null : () => _next(),
      children: [
        _Card(
          children: [
            _Row(
              label: 'Google Calendar',
              value: _google ? 'Connected' : null,
              placeholder: 'Connect',
              onTap: _google
                  ? null
                  : () => _connect(() async {
                      await CalendarService.connectAndGetWeekEvents(_weekStart);
                      if (mounted) {
                        setState(
                          () => _google =
                              CalendarService.connectionNotifier.value,
                        );
                      }
                    }),
            ),
            const Divider(height: 1, color: _line),
            _Row(
              label: 'Outlook',
              value: _outlook ? 'Connected' : null,
              placeholder: 'Connect',
              onTap: _outlook
                  ? null
                  : () => _connect(() async {
                      await OutlookCalendarService.connectAndGetWeekEvents(
                        _weekStart,
                      );
                      final signedIn =
                          await OutlookCalendarService.isSignedIn();
                      if (mounted) setState(() => _outlook = signedIn);
                    }),
            ),
          ],
        ),
      ],
    ),
    OnboardingStep.ai => _StepLayout(
      icon: Icons.auto_awesome_rounded,
      iconColor: const Color(0xFF534AB7),
      kicker: 'PRIVACY',
      title: 'Vivordo AI',
      body: aiConsentDisclosure,
      primary: _aiOn ? 'Continue' : 'Turn on Vivordo AI',
      onPrimary: _busy
          ? null
          : () => _next(
              _aiOn
                  ? null
                  : () async {
                      await AiConsent.grant(_uid);
                      _aiOn = true;
                    },
            ),
      secondary: _aiOn ? null : 'Not now',
      onSecondary: _busy ? null : () => _next(),
      children: [
        if (_aiOn) const _Connected('On'),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            onPressed: () =>
                openVivordoLink(context, Uri.parse(vivordoPrivacyUrl)),
            child: const Text('Privacy Policy'),
          ),
        ),
      ],
    ),
    OnboardingStep.notifications => _StepLayout(
      kicker: 'ALMOST DONE',
      title: 'Stay in the loop',
      body:
          'Morning check-in reminders, burnout warnings and updates from your '
          'Circle. Choose which ones in Settings.',
      primary: 'Allow notifications',
      onPrimary: _busy ? null : () => _next(_allowNotifications),
      secondary: 'Not now',
      onSecondary: _busy ? null : () => _next(),
      // Existing users already have these scores.
      children: [
        if (_steps.first != OnboardingStep.intro) ...const [
          SizedBox(height: 4),
          Text(
            'WHAT HAPPENS NEXT',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: .8,
              color: _purple,
            ),
          ),
          SizedBox(height: 10),
          _Bullet(Icons.wb_sunny_rounded, 'Tomorrow', 'your first Capacity'),
          _Bullet(
            Icons.directions_run_rounded,
            'In 2 weeks',
            'your Physical Health score',
          ),
          _Bullet(
            Icons.warning_amber_rounded,
            'In about 6 weeks',
            'the burnout check, once it knows your normal',
          ),
        ],
      ],
    ),
  };

  String get _healthName => defaultTargetPlatform == TargetPlatform.iOS
      ? 'Apple Health'
      : 'Health Connect';

  Future<void> _saveAbout() async {
    final name = _name.text.trim();
    await PersonalProfileService.saveAbout(birthYear: _birthYear, sex: _sex);
    if (name != (FirebaseAuth.instance.currentUser?.displayName ?? '')) {
      await UserService.updateDisplayName(name);
    }
  }

  Future<void> _saveWrapUp() => _userRef.set({
    // Nested map: set() stores dotted keys as literal field names. Null
    // means "it varies".
    'preferences': {'dayWrapUpMinutes': _wrapUpVaries ? null : _wrapUp},
  }, SetOptions(merge: true));

  Future<void> _connectHealth() async {
    final granted = await HealthService().ensureHealthAuthorization();
    // Records consent and syncs 30 days in the background; the sheet above
    // already asked, so this doesn't ask again. Apple's separate Cardio
    // Fitness sheet (VO₂ max) follows on Home.
    if (!granted) return;
    _healthConnected = true;
    unawaited(HealthService().enableAll());
    unawaited(_prefillSleep());
  }

  Future<void> _connectFitbit() => _connect(() async {
    try {
      await FitbitService.instance.connect();
      if (mounted) setState(() => _fitbit = true);
    } on FitbitAccountNotLinkedException {
      if (mounted) {
        showToast(
          context,
          "This Google account isn't linked to Google Health yet. "
          'Finish Fitbit in Settings later.',
        );
      }
    }
  });

  // Only a yes is saved: a stored false would block server pushes even after
  // someone allows notifications in iOS Settings.
  Future<void> _allowNotifications() async {
    if (!await NotificationService().requestPermission()) return;
    await _userRef.set({
      'preferences': {'notificationsEnabled': true},
    }, SetOptions(merge: true));
  }

  Future<void> _editMeasurements() async {
    final result =
        await showModalBottomSheet<(double, double, double?, DateTime)>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => MeasurementEditorSheet(
            title: 'Height and weight',
            profile: _profile,
          ),
        );
    if (result == null || !mounted) return;
    await _connect(() async {
      await PersonalProfileService.save(
        heightCm: result.$1,
        weightKg: result.$2,
        bodyFatPercent: result.$3,
        recordedAt: result.$4,
      );
      if (mounted) {
        setState(
          () => _profile = PersonalProfile(
            heightCm: result.$1,
            weightKg: result.$2,
            bodyFatPercent: result.$3,
          ),
        );
      }
    }, onError: "Couldn't save your measurements. Try again.");
  }
}

/// Light theme, light Cupertino pickers and a dark status bar, whatever the
/// phone's appearance (onboarding and account screens are light only).
Widget onboardingLight(Widget child) => AnnotatedRegion<SystemUiOverlayStyle>(
  value: SystemUiOverlayStyle.dark,
  child: Theme(
    data: VivordoTheme.light,
    child: CupertinoTheme(
      data: const CupertinoThemeData(brightness: Brightness.light),
      child: child,
    ),
  ),
);

String _feetInches(double cm) {
  final inches = (cm / 2.54).round();
  return '${inches ~/ 12}′ ${inches % 12}″';
}

class _StepLayout extends StatelessWidget {
  const _StepLayout({
    required this.kicker,
    required this.title,
    required this.body,
    required this.primary,
    required this.onPrimary,
    this.children = const [],
    this.secondary,
    this.onSecondary,
    this.icon,
    this.iconColor,
  });

  final String kicker, title, body, primary;
  final VoidCallback? onPrimary;
  final List<Widget> children;
  final String? secondary;
  final VoidCallback? onSecondary;
  final IconData? icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
          children: [
            if (icon != null) ...[
              // A ListView stretches its children; Align keeps the tile square.
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: iconColor!.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: iconColor, size: 26),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Text(
              kicker,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: .9,
                color: _purple,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                height: 1.2,
                color: _ink,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              body,
              style: const TextStyle(fontSize: 15, height: 1.45, color: _grey),
            ),
            const SizedBox(height: 22),
            ...children,
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          children: [
            SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton(
                onPressed: onPrimary,
                style: FilledButton.styleFrom(
                  backgroundColor: _purple,
                  disabledBackgroundColor: const Color(0xFFD1CEFF),
                  foregroundColor: Colors.white,
                  disabledForegroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  primary,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            if (secondary != null)
              TextButton(
                onPressed: onSecondary,
                child: Text(
                  secondary!,
                  style: const TextStyle(
                    color: _purple,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _line),
    ),
    child: Column(children: children),
  );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    this.value,
    this.placeholder = 'Choose',
    this.onTap,
  });

  final String label;
  final String? value;
  final String placeholder;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 15, color: _ink),
            ),
          ),
          Text(
            value ?? placeholder,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: value == null ? _purple : _grey,
            ),
          ),
          if (onTap != null)
            const Icon(Icons.chevron_right_rounded, color: _grey),
        ],
      ),
    ),
  );
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.icon, this.title, this.detail);

  final IconData icon;
  final String title, detail;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 22, color: _purple),
        const SizedBox(width: 12),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(text: ' · $detail'),
              ],
            ),
            style: const TextStyle(fontSize: 15, height: 1.35, color: _ink),
          ),
        ),
      ],
    ),
  );
}

class _Connected extends StatelessWidget {
  const _Connected(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      children: [
        const Icon(Icons.check_circle_rounded, color: Color(0xFF1D9E75)),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F6E56),
          ),
        ),
      ],
    ),
  );
}
