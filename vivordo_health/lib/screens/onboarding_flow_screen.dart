import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';

import '../src/services/ai_consent.dart';
import '../src/services/calendar_service.dart';
import '../src/services/day_record_service.dart';
import '../src/services/fitbit_service.dart';
import '../src/services/health_service.dart';
import '../src/services/notification_service.dart';
import '../src/services/outlook_calendar_service.dart';
import '../src/services/personal_profile_service.dart';
import '../src/services/user_service.dart';
import '../src/services/whoop_service.dart';
import '../src/utils/day_key.dart';
import '../src/utils/day_wrap_up.dart';
import '../src/utils/history_findings.dart';
import '../src/utils/sleep_schedule.dart';
import '../widgets/apple_ui.dart';
import '../widgets/birth_year_picker.dart';
import '../widgets/outlook_connect.dart';
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
  scores,
  notifications,
  history,
}

/// The required steps for this user, kept short so people see what Vivordo
/// found before the paywall: people who finished the old onboarding see a
/// "what's changed" intro first. The rest is [setupSteps], afterwards.
List<OnboardingStep> onboardingSteps(Map<String, dynamic>? userDoc) => [
  if (userDoc?['onboardingCompleted'] == true) OnboardingStep.intro,
  OnboardingStep.about,
  OnboardingStep.health,
  OnboardingStep.history,
];

/// Optional setup after onboarding, from Home's "Finish setting up" card
/// (`setupPending` on the user doc) and all of it also in Settings.
const setupSteps = [
  OnboardingStep.wrapUp,
  OnboardingStep.sleep,
  OnboardingStep.calendar,
  OnboardingStep.wearables,
  OnboardingStep.ai,
  OnboardingStep.scores,
  OnboardingStep.notifications,
];

const _purple = VivordoTheme.brand;

/// Shown by AuthGate after sign-in until [kOnboardingVersion] is saved
/// (docs: the onboarding-redesign idea). Every answer saves as its step is
/// completed, so quitting halfway loses nothing; answers already saved are
/// filled in.
class OnboardingFlowScreen extends StatefulWidget {
  const OnboardingFlowScreen({
    super.key,
    required this.userDoc,
    required this.onFinished,
    this.setup = false,
  });

  final Map<String, dynamic>? userDoc;
  final Future<void> Function() onFinished;

  /// The optional [setupSteps] after onboarding, which can be closed.
  final bool setup;

  @override
  State<OnboardingFlowScreen> createState() => _OnboardingFlowScreenState();
}

class _OnboardingFlowScreenState extends State<OnboardingFlowScreen> {
  final _pages = PageController();
  late final List<OnboardingStep> _steps = widget.setup
      ? setupSteps
      : onboardingSteps(widget.userDoc);
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

  /// Numbers (the default) or words mode (`preferences.showScoreNumbers`).
  late bool _showNumbers =
      (widget.userDoc?['preferences'] as Map?)?['showScoreNumbers'] != false;
  bool _google = false;
  bool _outlook = false;
  bool _aiOn = false;

  /// The history step: whether a calendar is connected (null until
  /// checked), and what was found once the import is scored.
  bool _historyStarted = false;
  bool? _historyCalendar;
  bool _historyDone = false;
  HistoryFindings? _findings;

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
      AiConsent.granted(_uid),
      OutlookCalendarService.isSignedIn(),
    ]);
    if (!mounted) return;
    setState(() {
      _google = results[0];
      _aiOn = results[1];
      _outlook = results[2];
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
          if (widget.setup)
            'setupPending': false
          else ...{
            'onboardingVersion': kOnboardingVersion,
            'onboardingCompleted': true,
            'onboardingCompletedAt': FieldValue.serverTimestamp(),
            // Home offers the rest of setup until it's done or dismissed.
            'setupPending': true,
          },
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        // A calendar connected during setup: read its last 4 weeks now, as
        // the history step does during onboarding.
        if (widget.setup) {
          unawaited(
            HealthService().syncWithHistory(recent: false, calendar: true),
          );
        }
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

  @override
  Widget build(BuildContext context) => onboardingTheme(
    Scaffold(
      backgroundColor: context.vivordoColors.page,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 4),
              child: Row(
                children: [
                  // Setup is optional: its first step closes instead.
                  if (widget.setup && _index == 0)
                    IconButton(
                      tooltip: 'Close',
                      onPressed: _busy
                          ? null
                          : () => Navigator.maybePop(context),
                      icon: Icon(
                        CupertinoIcons.xmark,
                        size: 18,
                        color: context.vivordoColors.textPrimary,
                      ),
                    )
                  else
                    IconButton(
                      tooltip: 'Back',
                      onPressed: _index == 0 || _busy
                          ? null
                          : () => _pages.previousPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOutCubic,
                            ),
                      icon: Icon(
                        CupertinoIcons.back,
                        size: 18,
                        color: _index == 0
                            ? Colors.transparent
                            : context.vivordoColors.textPrimary,
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
                                color: i <= _index
                                    ? _purple
                                    : context.vivordoColors.border,
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
                onPageChanged: (i) {
                  setState(() => _index = i);
                  if (_steps[i] == OnboardingStep.history) {
                    unawaited(_startHistory());
                  }
                },
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
      kicker: 'Welcome back',
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
      kicker: 'About you',
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
            Divider(height: 1, color: context.vivordoColors.border),
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
            Divider(height: 1, color: context.vivordoColors.border),
            _Row(
              label: 'Height and weight',
              value: _profile.heightCm == null || _profile.weightKg == null
                  ? null
                  : '${context.watch<ThemeController>().units.formatHeight(_profile.heightCm!)} · '
                        '${context.watch<ThemeController>().units.formatBodyWeight(_profile.weightKg!, decimals: 0)}',
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
        Text(
          'Height and weight are optional, and sharpen the cardio fitness '
          'estimate. You can change any of this later in your profile.',
          style: TextStyle(
            fontSize: 12,
            color: context.vivordoColors.textSecondary,
          ),
        ),
      ],
    ),
    OnboardingStep.wrapUp => _StepLayout(
      kicker: 'Your day',
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
                  brightness: Theme.of(context).brightness,
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
              child: MergeSemantics(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'It varies day to day',
                        style: TextStyle(
                          fontSize: 15,
                          color: context.vivordoColors.textPrimary,
                        ),
                      ),
                    ),
                    AppSwitch(
                      value: _wrapUpVaries,
                      onChanged: (value) =>
                          setState(() => _wrapUpVaries = value),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    ),
    OnboardingStep.sleep => _StepLayout(
      kicker: 'Your sleep',
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
            style: TextStyle(
              fontSize: 12,
              color: context.vivordoColors.textSecondary,
            ),
          ),
        ],
      ],
    ),
    OnboardingStep.health => _StepLayout(
      icon: Icons.favorite_rounded,
      iconColor: const Color(0xFFE24B4A),
      kicker: 'Connect',
      title: 'Connect $_healthName',
      body:
          'Your scores come from this. Vivordo only reads your data; it never '
          'writes to $_healthName.',
      // One "Continue" that opens the system sheet, where people can also
      // decline (HIG pre-alert screens).
      primary: 'Continue',
      onPrimary: _busy
          ? null
          : () => _next(_healthConnected ? null : _connectHealth),
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
      kicker: 'Connect',
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
            Divider(height: 1, color: context.vivordoColors.border),
            _Row(
              label: 'Fitbit',
              value: _fitbit ? 'Connected' : null,
              placeholder: 'Connect',
              onTap: _fitbit ? null : _connectFitbit,
            ),
            if (defaultTargetPlatform == TargetPlatform.iOS) ...[
              Divider(height: 1, color: context.vivordoColors.border),
              const _Row(label: 'Apple Watch', value: 'Through Apple Health'),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'No wearable? Your phone and morning check-ins still work.',
          style: TextStyle(
            fontSize: 12,
            color: context.vivordoColors.textSecondary,
          ),
        ),
      ],
    ),
    OnboardingStep.calendar => _StepLayout(
      icon: CupertinoIcons.calendar,
      iconColor: const Color(0xFF185FA5),
      kicker: 'Connect',
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
            if (OutlookCalendarService.enabled) ...[
              Divider(height: 1, color: context.vivordoColors.border),
              _Row(
                label: 'Outlook',
                value: _outlook ? 'Connected' : null,
                placeholder: 'Connect',
                onTap: _outlook
                    ? null
                    : () => _connect(() async {
                        final connected = await connectOutlook(context);
                        if (mounted) setState(() => _outlook = connected);
                      }),
              ),
            ],
          ],
        ),
      ],
    ),
    OnboardingStep.ai => _StepLayout(
      icon: Icons.auto_awesome_rounded,
      iconColor: const Color(0xFF534AB7),
      kicker: 'Privacy',
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
    OnboardingStep.scores => _StepLayout(
      kicker: 'Your scores',
      title: 'How do you want to see your scores?',
      body: 'You can change this any time in Settings.',
      primary: 'Continue',
      onPrimary: _busy
          ? null
          : () => _next(
              () => _userRef.set({
                'preferences': {'showScoreNumbers': _showNumbers},
              }, SetOptions(merge: true)),
            ),
      children: [
        _ScoreStyleOption(
          title: 'Numbers',
          example: 'Stress 47%, Capacity 78, Demand 18',
          selected: _showNumbers,
          onTap: () => setState(() => _showNumbers = true),
        ),
        const SizedBox(height: 10),
        _ScoreStyleOption(
          title: 'Words',
          example:
              '"Steady. Your usual energy, a light day." The same '
              'insights, nothing to chase.',
          selected: !_showNumbers,
          onTap: () => setState(() => _showNumbers = false),
        ),
        const SizedBox(height: 10),
        Text(
          'Hours slept, heart rate and steps always show.',
          style: TextStyle(
            fontSize: 12,
            color: context.vivordoColors.textSecondary,
          ),
        ),
      ],
    ),
    OnboardingStep.history => _historyPage(),
    OnboardingStep.notifications => _StepLayout(
      kicker: 'Almost done',
      title: 'Stay in the loop',
      body:
          'Morning check-in reminders, burnout warnings and updates from your '
          'Circle. Choose which ones in Settings.',
      primary: 'Continue',
      onPrimary: _busy ? null : () => _next(_allowNotifications),
      // Existing users already have these scores, and with Health connected
      // the next step reads them from the history.
      children: [
        // Only for someone new without Health; setup comes after the
        // history step, which already said what's next.
        if (!widget.setup &&
            _steps.first != OnboardingStep.intro &&
            !_healthConnected) ...const [
          SizedBox(height: 4),
          Text(
            'What happens next',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
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

  // The last step: reads the history (docs/scores.md §4) now that Health,
  // the calendar and AI consent are all set, then shows what it found.
  Widget _historyPage() {
    if (!_healthConnected && _historyCalendar == false) {
      return _StepLayout(
        kicker: 'All set',
        title: "You're ready",
        body:
            'Connect $_healthName or a calendar any time in Settings, and '
            'Vivordo will read your history then.',
        primary: 'Continue',
        onPrimary: _busy ? null : () => _next(),
      );
    }
    if (!_historyDone) {
      return _StepLayout(
        kicker: 'Almost there',
        title: 'Getting to know you',
        body:
            'Reading your last 3 months so your scores know what\'s normal '
            'for you from today.',
        primary: 'Working…',
        onPrimary: null,
        secondary: 'Continue in the background',
        onSecondary: _busy ? null : () => _next(),
        children: [
          ValueListenableBuilder<String?>(
            valueListenable: HealthService.historyStep,
            builder: (context, step, _) {
              const order = ['health', 'calendar', 'scoring', 'done'];
              final at = step == null ? -1 : order.indexOf(step);
              _HistoryState state(String part) {
                final i = order.indexOf(part);
                return at > i
                    ? _HistoryState.done
                    : at == i
                    ? _HistoryState.running
                    : _HistoryState.waiting;
              }

              return Column(
                children: [
                  if (_healthConnected)
                    _HistoryRow(
                      'Sleep and heart',
                      'Last 3 months',
                      state('health'),
                    ),
                  if (_historyCalendar == true)
                    _HistoryRow('Calendar', 'Last 4 weeks', state('calendar')),
                  _HistoryRow('Scoring your days', null, state('scoring')),
                ],
              );
            },
          ),
        ],
      );
    }
    final found = _findings;
    // Nothing to show yet (a new phone, or too little history): no "found".
    if (found == null || (found.insight == null && found.usuals.isEmpty)) {
      return _StepLayout(
        kicker: 'All set',
        title: "You're all set",
        body: _healthConnected
            ? 'Vivordo is reading your $_healthName data and will learn your '
                  'usual over the next couple of weeks. Your first Capacity '
                  'arrives tomorrow.'
            : 'Vivordo will learn your usual over the next couple of weeks.',
        primary: 'Continue',
        onPrimary: _busy ? null : () => _next(),
      );
    }
    return _StepLayout(
      kicker: 'All set',
      title: "Here's what we found",
      body: 'Your scores compare with these from today.',
      primary: 'Continue',
      onPrimary: _busy ? null : () => _next(),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.vivordoColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _purple.withValues(alpha: .35),
              width: 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'From your last 3 months',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: context.vivordoColors.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                found?.insight ??
                    'Vivordo will point out your patterns as it learns your '
                        'days.',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                  color: context.vivordoColors.textPrimary,
                ),
              ),
              if (found?.basis case final basis?) ...[
                const SizedBox(height: 6),
                Text(
                  '$basis Vivordo will keep checking this.',
                  style: TextStyle(
                    fontSize: 13,
                    color: context.vivordoColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (found != null && found.usuals.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            'Your usual',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: context.vivordoColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.3,
            children: [
              for (final usual in found.usuals)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: context.vivordoColors.card,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        usual.value,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: context.vivordoColors.textPrimary,
                        ),
                      ),
                      Text(
                        usual.label,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.vivordoColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _startHistory() async {
    if (_historyStarted) return;
    _historyStarted = true;
    final calendar = await DayRecordService.calendarConnected();
    if (!mounted) return;
    setState(() => _historyCalendar = calendar);
    if (_healthConnected || calendar) {
      // Queued behind the import Health started earlier, so this one adds
      // the calendar now that it's connected and AI consent is set.
      await HealthService().syncWithHistory(recent: false, calendar: true);
    }
    final findings = await _loadFindings();
    if (mounted) {
      setState(() {
        _findings = findings;
        _historyDone = true;
      });
    }
  }

  /// The last 90 days' scores as findings; null when they can't be read.
  Future<HistoryFindings?> _loadFindings() async {
    try {
      final today = DateTime.now();
      final snapshot = await _userRef
          .collection('scores_daily')
          .where(
            FieldPath.documentId,
            isGreaterThanOrEqualTo: localDayKey(
              today.subtract(const Duration(days: 90)),
            ),
          )
          .get();
      double? n(Object? value) => (value as num?)?.toDouble();
      return historyFindings(
        [
          for (final doc in snapshot.docs)
            if (DateTime.tryParse(doc.id) case final day?)
              (
                day: day,
                capacity: n(doc.data()['capacity']?['score']),
                sleepHours: n(doc.data()['capacity']?['sleepHours']),
                sleepNeed: n(doc.data()['capacity']?['sleepNeed']),
                hrv: n(doc.data()['capacity']?['hrv']),
                restingHr: doc.data()['capacity']?['restingHrIgnored'] == true
                    ? null
                    : n(doc.data()['capacity']?['restingHr']),
                restingHrKind:
                    doc.data()['capacity']?['restingHrKind'] as String?,
                effort: n(doc.data()['effort']?['total']),
                afterHoursMinutes: n(
                  doc.data()['effort']?['afterHoursMinutes'],
                ),
              ),
        ],
        today: DateTime(today.year, today.month, today.day),
        numbers: _showNumbers,
      );
    } catch (error) {
      debugPrint('Onboarding history findings failed: $error');
      return null;
    }
  }

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

/// Onboarding and account screens follow the phone's appearance, on iOS's
/// grouped grey page in light mode so their white cards stand out.
Widget onboardingTheme(Widget child) => Builder(
  builder: (context) {
    final theme = Theme.of(context);
    if (theme.brightness == Brightness.dark) return child;
    return Theme(
      data: theme.copyWith(
        extensions: [
          context.vivordoColors.copyWith(page: const Color(0xFFF2F2F7)),
        ],
      ),
      child: child,
    );
  },
);

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
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _purple,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                height: 1.2,
                color: context.vivordoColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              body,
              style: TextStyle(
                fontSize: 15,
                height: 1.45,
                color: context.vivordoColors.textSecondary,
              ),
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
                  disabledBackgroundColor: _purple.withValues(alpha: .35),
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

/// One way to see scores, picked like a radio button.
class _ScoreStyleOption extends StatelessWidget {
  const _ScoreStyleOption({
    required this.title,
    required this.example,
    required this.selected,
    required this.onTap,
  });

  final String title, example;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: '$title. $example',
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? _purple.withValues(alpha: .12)
              : context.vivordoColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? _purple : context.vivordoColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: context.vivordoColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    example,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: context.vivordoColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected ? _purple : context.vivordoColors.border,
            ),
          ],
        ),
      ),
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    decoration: BoxDecoration(
      color: context.vivordoColors.card,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: context.vivordoColors.border),
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
              style: TextStyle(
                fontSize: 15,
                color: context.vivordoColors.textPrimary,
              ),
            ),
          ),
          Text(
            value ?? placeholder,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: value == null
                  ? _purple
                  : context.vivordoColors.textSecondary,
            ),
          ),
          if (onTap != null)
            Icon(
              CupertinoIcons.chevron_right,
              color: context.vivordoColors.textSecondary,
            ),
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
            style: TextStyle(
              fontSize: 15,
              height: 1.35,
              color: context.vivordoColors.textPrimary,
            ),
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
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: context.vivordoColors.success,
          ),
        ),
      ],
    ),
  );
}

enum _HistoryState { waiting, running, done }

/// One part of the history import on "Getting to know you".
class _HistoryRow extends StatelessWidget {
  const _HistoryRow(this.title, this.detail, this.state);

  final String title;
  final String? detail;
  final _HistoryState state;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    decoration: BoxDecoration(
      color: context.vivordoColors.card,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        SizedBox(
          width: 22,
          height: 22,
          child: switch (state) {
            _HistoryState.done => const Icon(
              Icons.check_circle_rounded,
              color: Color(0xFF1D9E75),
              size: 22,
            ),
            _HistoryState.running => const Padding(
              padding: EdgeInsets.all(2),
              child: CupertinoActivityIndicator(color: _purple),
            ),
            _HistoryState.waiting => Icon(
              Icons.circle_outlined,
              color: context.vivordoColors.border,
              size: 22,
            ),
          },
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 15,
              color: context.vivordoColors.textPrimary,
            ),
          ),
        ),
        if (detail != null)
          Text(
            detail!,
            style: TextStyle(
              fontSize: 13,
              color: context.vivordoColors.textSecondary,
            ),
          ),
      ],
    ),
  );
}
