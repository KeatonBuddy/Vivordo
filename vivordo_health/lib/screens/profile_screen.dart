import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:vivordo_health/src/services/calendar_service.dart';
import 'package:vivordo_health/src/services/outlook_calendar_service.dart';
import 'package:vivordo_health/src/services/user_service.dart';
import 'package:vivordo_health/src/services/health_service.dart';
import 'package:vivordo_health/src/services/fitbit_service.dart';
import 'package:vivordo_health/src/services/whoop_service.dart';
import 'package:vivordo_health/src/services/notification_service.dart';
import 'package:vivordo_health/src/services/check_in_reminder.dart';
import 'package:vivordo_health/src/services/wind_down_reminder.dart';
import 'package:vivordo_health/src/services/analytics_service.dart';
import 'package:vivordo_health/src/services/account_deletion_service.dart';
import 'package:vivordo_health/src/models/user_model.dart';
import 'login_screen.dart';
import 'blocked_users_screen.dart';
import '../widgets/privacy_support_links.dart';
import '../src/services/ai_consent.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';
import 'package:vivordo_health/src/utils/day_wrap_up.dart';
import 'package:vivordo_health/widgets/vivordo_time_picker.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  bool _isEmailVerificationSignOut = false;
  bool _isAccountDeletionSignOut = false;

  bool _isGoogleCalendarConnected = false;
  bool _isUpdatingGoogleCalendar = false;
  bool _isOutlookCalendarConnected = false;
  bool _isUpdatingOutlookCalendar = false;
  bool _isUpdatingFitbit = false;
  bool _isUpdatingWhoop = false;
  bool _isUpdatingScanReminder = false;
  bool _isUpdatingCheckInReminder = false;
  bool _isUpdatingCircleNotifications = false;
  bool _isUpdatingFitnessNotifications = false;

  // Bug report
  final TextEditingController _bugReportController = TextEditingController();
  bool _isDeletingAccount = false;

  StreamSubscription<User?>? _authSubscription;

  // Cached Firestore stream — MUST be created once in initState and reused.
  // If we create it inside build() a new stream object is made on every
  // rebuild, StreamBuilder detects the change, resets to 'waiting', and the
  // screen spins forever.
  late Stream<DocumentSnapshot<Map<String, dynamic>>> _userDocStream;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    final uid = FirebaseAuth.instance.currentUser?.uid;
    _userDocStream = uid != null
        ? FirebaseFirestore.instance.collection('users').doc(uid).snapshots()
        : const Stream.empty();

    CalendarService.connectionNotifier.addListener(
      _handleGoogleCalendarConnectionChange,
    );
    _refreshGoogleCalendarConnection();
    if (OutlookCalendarService.enabled) {
      _refreshOutlookCalendarConnection();
    }

    // Skip the first emission — it just reflects current login state, not a change
    bool isFirstEmission = true;
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (isFirstEmission) {
        isFirstEmission = false;
        return;
      }
      if (user == null && mounted) {
        final message = switch ((
          _isEmailVerificationSignOut,
          _isAccountDeletionSignOut,
        )) {
          (true, _) =>
            'Email verified! Please log in again with your new email.',
          (_, true) => 'Your Vivordo account has been deleted.',
          _ => 'You have been signed out.',
        };

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 4),
          ),
        );
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
      }
    });

    // NOTE: We do NOT call _checkEmailSync() here anymore.
    // Cleanup of pendingEmail now happens in AuthService.emailLogin,
    // so by the time the user reaches this screen it is already clean.
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _bugReportController.dispose();
    CalendarService.connectionNotifier.removeListener(
      _handleGoogleCalendarConnectionChange,
    );
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Sends the bug report. Returns whether it was sent.
  Future<bool> _submitBugReport() async {
    final message = _bugReportController.text.trim();
    if (message.isEmpty) return false;
    try {
      await UserService.submitBugReport(message);
      if (!mounted) return true;
      _bugReportController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thanks! Your bug report has been sent.')),
      );
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not send report: $e')));
      }
      return false;
    }
  }

  Future<void> _deleteAccount() async {
    final confirmation = await _showAccountDeletionConfirmation();
    if (confirmation == null || !mounted) return;

    setState(() {
      _isDeletingAccount = true;
      _isAccountDeletionSignOut = true;
    });
    try {
      await AccountDeletionService.deleteAccount(
        password: confirmation.password,
      );
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(() => _isAccountDeletionSignOut = false);
      final message = switch (error.code) {
        'wrong-password' || 'invalid-credential' =>
          'That password is incorrect. Your account was not deleted.',
        'user-mismatch' => 'Sign in with the same account to confirm deletion.',
        _ => error.message ?? 'Your account could not be deleted.',
      };
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) return;
      setState(() => _isAccountDeletionSignOut = false);
      final message = error is FirebaseFunctionsException
          ? error.message ?? 'Your account could not be deleted.'
          : error.toString().replaceFirst('Bad state: ', '');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _isDeletingAccount = false);
    }
  }

  Future<_AccountDeletionConfirmation?>
  _showAccountDeletionConfirmation() async {
    final passwordController = TextEditingController();
    final needsPassword = AccountDeletionService.requiresPassword;
    var passwordReady = !needsPassword;
    try {
      return await showDialog<_AccountDeletionConfirmation>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Permanently delete account?'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 240, maxWidth: 320),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'This permanently deletes your Vivordo profile, health '
                        'and wellness history, journal entries, workouts, '
                        'insights, Circle content, challenges, connected-provider '
                        'credentials, and uploaded profile photo. This cannot be '
                        'undone.',
                      ),
                      if (needsPassword) ...[
                        const SizedBox(height: 16),
                        TextField(
                          controller: passwordController,
                          autofocus: true,
                          obscureText: true,
                          enableSuggestions: false,
                          autocorrect: false,
                          onChanged: (value) => setDialogState(
                            () => passwordReady = value.isNotEmpty,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Current password',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      SlideToDelete(
                        enabled: passwordReady,
                        onConfirmed: () => Navigator.of(dialogContext).pop(
                          _AccountDeletionConfirmation(
                            password: needsPassword
                                ? passwordController.text
                                : null,
                          ),
                        ),
                      ),
                      if (!passwordReady) ...[
                        const SizedBox(height: 8),
                        const Center(
                          child: Text(
                            'Enter your password to enable the slider.',
                            style: TextStyle(fontSize: 12),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      passwordController.dispose();
    }
  }

  void _handleGoogleCalendarConnectionChange() {
    if (!mounted) return;
    setState(() {
      _isGoogleCalendarConnected = CalendarService.connectionNotifier.value;
    });
  }

  Future<void> _refreshGoogleCalendarConnection() async {
    final hasAccess = await CalendarService.hasCalendarAccess();
    if (mounted) setState(() => _isGoogleCalendarConnected = hasAccess);
  }

  Future<void> _updateGoogleCalendarConnection() async {
    setState(() => _isUpdatingGoogleCalendar = true);
    try {
      if (_isGoogleCalendarConnected) {
        await CalendarService.signOut();
      } else {
        final today = DateTime.now();
        final weekStart = today.subtract(Duration(days: today.weekday - 1));
        await CalendarService.connectAndGetWeekEvents(
          DateTime(weekStart.year, weekStart.month, weekStart.day),
        );
      }

      final isConnected = CalendarService.connectionNotifier.value;
      if (mounted) {
        setState(() => _isGoogleCalendarConnected = isConnected);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isConnected
                  ? 'Google Calendar has been signed in.'
                  : 'Google Calendar has been logged out.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update Google Calendar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdatingGoogleCalendar = false);
    }
  }

  Future<void> _refreshOutlookCalendarConnection() async {
    final isConnected = await OutlookCalendarService.isSignedIn();
    if (mounted) {
      setState(() => _isOutlookCalendarConnected = isConnected);
    }
  }

  Future<void> _updateOutlookCalendarConnection() async {
    setState(() => _isUpdatingOutlookCalendar = true);
    try {
      if (_isOutlookCalendarConnected) {
        await OutlookCalendarService.signOut();
      } else {
        final today = DateTime.now();
        final weekStart = today.subtract(Duration(days: today.weekday - 1));
        await OutlookCalendarService.connectAndGetWeekEvents(
          DateTime(weekStart.year, weekStart.month, weekStart.day),
        );
      }

      final isConnected = await OutlookCalendarService.isSignedIn();
      if (mounted) {
        setState(() => _isOutlookCalendarConnected = isConnected);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isConnected
                  ? 'Outlook Calendar has been signed in.'
                  : 'Outlook Calendar has been logged out.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update Outlook Calendar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdatingOutlookCalendar = false);
    }
  }

  Future<void> _updateFitbitConnection(bool isConnected) async {
    if (_isUpdatingFitbit) return;
    setState(() => _isUpdatingFitbit = true);
    try {
      if (isConnected) {
        await FitbitService.instance.disconnect();
      } else {
        await FitbitService.instance.connect();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isConnected
                  ? 'Fitbit has been disconnected.'
                  : 'Fitbit connected and the last 30 days were synced.',
            ),
          ),
        );
      }
    } on FitbitAccountNotLinkedException catch (error) {
      if (mounted) await _showGoogleHealthSetupDialog(error.setupUrl);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Fitbit could not be updated. Please try again shortly.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdatingFitbit = false);
    }
  }

  Future<bool?> _showWhoopDisconnectDialog() {
    var deleteImportedData = false;
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Disconnect WHOOP?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Vivordo will stop syncing new WHOOP data and revoke access '
                'to your WHOOP account.',
              ),
              const SizedBox(height: 12),
              RadioGroup<bool>(
                groupValue: deleteImportedData,
                onChanged: (value) =>
                    setDialogState(() => deleteImportedData = value!),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const RadioListTile<bool>(
                      contentPadding: EdgeInsets.zero,
                      value: false,
                      title: Text('Disconnect and keep history'),
                      subtitle: Text(
                        'Keep measurements already imported into Vivordo.',
                      ),
                    ),
                    const RadioListTile<bool>(
                      contentPadding: EdgeInsets.zero,
                      value: true,
                      title: Text('Disconnect and delete WHOOP data'),
                      subtitle: Text(
                        'Delete WHOOP measurements and invalidate affected scores.',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, deleteImportedData),
              child: const Text('Disconnect'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateWhoopConnection(bool isConnected) async {
    if (_isUpdatingWhoop) return;
    final deleteImportedData = isConnected
        ? await _showWhoopDisconnectDialog()
        : null;
    if (isConnected && deleteImportedData == null) return;
    setState(() => _isUpdatingWhoop = true);
    try {
      if (isConnected) {
        await WhoopService.instance.disconnect(
          deleteImportedData: deleteImportedData!,
        );
      } else {
        await WhoopService.instance.connect();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isConnected
                  ? deleteImportedData!
                        ? 'WHOOP has been disconnected and imported WHOOP '
                              'data has been deleted. Affected scores will be '
                              'recalculated when new data is available.'
                        : 'WHOOP has been disconnected. Previously imported '
                              'WHOOP data remains in Vivordo.'
                  : 'WHOOP connected and the last 30 days were synced.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'WHOOP could not be updated. Please try again shortly.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdatingWhoop = false);
    }
  }

  Future<void> _syncWhoop() async {
    if (_isUpdatingWhoop) return;
    setState(() => _isUpdatingWhoop = true);
    try {
      await WhoopService.instance.sync(daysBack: 30);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('WHOOP data is up to date.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'WHOOP could not be synced. Please try again shortly.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdatingWhoop = false);
    }
  }

  Future<void> _syncFitbit() async {
    if (_isUpdatingFitbit) return;
    setState(() => _isUpdatingFitbit = true);
    try {
      await FitbitService.instance.sync(daysBack: 30);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fitbit data is up to date.')),
        );
      }
    } on FitbitAccountNotLinkedException catch (error) {
      if (mounted) await _showGoogleHealthSetupDialog(error.setupUrl);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Fitbit could not be synced. Please try again shortly.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdatingFitbit = false);
    }
  }

  Future<void> _resetAiConsent() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await AiConsent.revoke(uid);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('AI consent reset. You will be asked again next time.'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not reset consent. Please try again.'),
        ),
      );
    }
  }

  Future<void> _showGoogleHealthSetupDialog(Uri setupUrl) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Finish Google Health setup'),
        content: const Text(
          'This Google account is not linked to Google Health yet. Complete '
          'the setup using the same account that owns your Fitbit data, then '
          'return to Vivordo and sync again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              final opened = await launchUrl(
                setupUrl,
                mode: LaunchMode.externalApplication,
              );
              if (!opened && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Could not open Google Health setup.'),
                  ),
                );
              }
            },
            child: const Text('Open setup'),
          ),
        ],
      ),
    );
  }

  Future<void> _setPreference(String field, bool value) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'preferences': {field: value},
    }, SetOptions(merge: true));
  }

  /// Runs a settings change, saying so if it fails.
  Future<void> _setPreferenceWith(Future<void> Function() change) async {
    try {
      await change();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't update that setting.")),
        );
      }
    }
  }

  Future<void> _setWindDownReminder(bool enabled) async {
    try {
      await WindDownReminders.setEnabled(enabled);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't update your reminder.")),
        );
      }
    }
  }

  Future<void> _updateReminderPreference({
    required String field,
    required bool enabled,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final isScanReminder = field == 'scanReminderEnabled';
    final isCircleNotification = field == 'circleNotificationsEnabled';
    final isFitnessNotification = field == 'fitnessNotificationsEnabled';
    final isUpdating = isScanReminder
        ? _isUpdatingScanReminder
        : isCircleNotification
        ? _isUpdatingCircleNotifications
        : isFitnessNotification
        ? _isUpdatingFitnessNotifications
        : _isUpdatingCheckInReminder;
    if (isUpdating) {
      return;
    }

    setState(() {
      if (isScanReminder) {
        _isUpdatingScanReminder = true;
      } else if (isCircleNotification) {
        _isUpdatingCircleNotifications = true;
      } else if (isFitnessNotification) {
        _isUpdatingFitnessNotifications = true;
      } else {
        _isUpdatingCheckInReminder = true;
      }
    });

    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'preferences.$field': enabled,
      });
      if (isScanReminder) {
        await NotificationService().setDailyScanRemindersEnabled(enabled);
      } else if (isFitnessNotification) {
        await NotificationService().setFitnessNotificationsEnabled(enabled);
      } else if (!isCircleNotification) {
        await NotificationService().setCalendarCheckInReminderEnabled(enabled);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update reminder settings.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          if (isScanReminder) {
            _isUpdatingScanReminder = false;
          } else if (isCircleNotification) {
            _isUpdatingCircleNotifications = false;
          } else if (isFitnessNotification) {
            _isUpdatingFitnessNotifications = false;
          } else {
            _isUpdatingCheckInReminder = false;
          }
        });
      }
    }
  }

  /// When the person's main work or classes usually end. Plans after it
  /// count as after hours in Demand and Effort (docs/scores.md).
  Future<void> _chooseDayWrapUp(int current) async {
    final choice = await showCupertinoModalPopup<String>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: const Text(
          'When do you usually wrap up your main work or classes?',
        ),
        message: const Text('Plans after this count as your own time.'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(sheetContext, 'time'),
            child: const Text('Choose a time'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(sheetContext, 'varies'),
            child: const Text('It varies'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetContext),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (choice == null || !mounted) return;

    int? minutes;
    if (choice == 'time') {
      final start = current - current % 15;
      final selected = await showVivordoTimePicker(
        context: context,
        initialTime: TimeOfDay(hour: start ~/ 60, minute: start % 60),
        title: 'End of day',
        minuteInterval: 15,
      );
      if (selected == null || !mounted) return;
      minutes = selected.hour * 60 + selected.minute;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'preferences.dayWrapUpMinutes': minutes,
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update your end of day.')),
        );
      }
    }
  }

  String _formatReminderTime(int minutes) {
    final hour24 = minutes ~/ 60;
    final minute = minutes % 60;
    final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    final suffix = hour24 >= 12 ? 'PM' : 'AM';
    return '$hour12:${minute.toString().padLeft(2, '0')} $suffix';
  }

  Future<void> _chooseScanReminderTime({
    required List<int> reminderTimes,
    int? index,
  }) async {
    final isAdding = index == null;
    final currentMinutes = isAdding
        ? (reminderTimes.last + 4 * 60) % (24 * 60)
        : reminderTimes[index!];
    final selected = await showVivordoTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: currentMinutes ~/ 60,
        minute: currentMinutes % 60,
      ),
      title: 'Reminder Time',
    );
    if (selected == null || !mounted) return;

    final selectedMinutes = selected.hour * 60 + selected.minute;
    final updatedTimes = [...reminderTimes];
    final existingTime = index == null ? null : reminderTimes[index];
    if (updatedTimes.contains(selectedMinutes) &&
        existingTime != selectedMinutes) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That reminder time already exists.')),
      );
      return;
    }
    if (isAdding) {
      updatedTimes.add(selectedMinutes);
    } else {
      updatedTimes[index!] = selectedMinutes;
    }
    updatedTimes.sort();
    await _saveScanReminderTimes(updatedTimes);
  }

  Future<void> _removeScanReminderTime(
    List<int> reminderTimes,
    int index,
  ) async {
    if (reminderTimes.length <= 1) return;
    final updatedTimes = [...reminderTimes]..removeAt(index);
    await _saveScanReminderTimes(updatedTimes);
  }

  Future<void> _saveScanReminderTimes(List<int> reminderTimes) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'preferences.scanReminderTimes': reminderTimes,
        'preferences.scanReminderMorningMinutes': FieldValue.delete(),
        'preferences.scanReminderEveningMinutes': FieldValue.delete(),
      });
      await NotificationService().setDailyScanReminderTimes(reminderTimes);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update reminder time.')),
        );
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Only check when the user returns to the app — this handles the case
    // where they tap the verification link while the app is already open
    if (state == AppLifecycleState.resumed) {
      _checkEmailSync();
      if (OutlookCalendarService.enabled) {
        _refreshOutlookCalendarConnection();
      }
    }
  }

  Future<void> _checkEmailSync() async {
    final didLogout = await UserService.syncEmailWithAuth();
    if (didLogout) {
      _isEmailVerificationSignOut = true;
    }
    // Navigation handled by authStateChanges listener
  }

  void _showEditDialog(
    BuildContext context,
    String field,
    String currentValue,
  ) {
    final TextEditingController controller = TextEditingController(
      text: currentValue,
    );
    // Only used when field == "Password" — Firebase always requires proof of
    // the current password (via reauthentication) before it will accept a
    // new one, so we collect it up front instead of dead-ending on a
    // requires-recent-login error after the fact.
    final TextEditingController currentPasswordController =
        TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Edit $field'),
          content: field == "Password"
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: currentPasswordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Current Password',
                      ),
                    ),
                    TextField(
                      controller: controller,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'New Password',
                      ),
                    ),
                  ],
                )
              : TextField(
                  controller: controller,
                  decoration: InputDecoration(labelText: field),
                ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  if (field == "Name") {
                    await UserService.updateDisplayName(controller.text);
                  } else if (field == "Email") {
                    await UserService.updateEmail(controller.text);
                  } else if (field == "Password") {
                    if (controller.text.length < 6) {
                      throw FirebaseAuthException(
                        code: 'weak-password',
                        message: 'Password should be at least 6 characters',
                      );
                    }
                    await UserService.reauthenticate(
                      currentPasswordController.text,
                    );
                    await UserService.updatePassword(controller.text);
                  }

                  if (mounted) {
                    Navigator.pop(context);

                    final message = field == "Email"
                        ? 'Verification email sent to ${controller.text}. Tap the link to confirm your new email.'
                        : '$field updated successfully!';

                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(message)));
                  }
                } on FirebaseAuthException catch (e) {
                  String errorMessage = 'Error: ${e.message}';
                  if (e.code == 'requires-recent-login') {
                    errorMessage =
                        'For security, please log out and log back in to change your $field.';
                  } else if (e.code == 'wrong-password' ||
                      e.code == 'invalid-credential') {
                    errorMessage = 'Current password is incorrect.';
                  } else if (e.code == 'weak-password') {
                    errorMessage = e.message ?? 'Password is too weak.';
                  }
                  if (mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(errorMessage)));
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: ${e.toString()}')),
                    );
                  }
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  static const _green = Color(0xFF10B981);
  static const _orange = Color(0xFFF97316);
  static const _red = Color(0xFFFF3B30);

  @override
  Widget build(BuildContext context) {
    // Build is driven entirely by _userDocStream which was cached in initState.
    // We do NOT call context.watch<User?>() here — that triggers extra rebuilds
    // and can cause a spinner loop because the Provider's initialData is null.
    // Sign-out is handled by the _authSubscription listener in initState.
    return StreamBuilder<DocumentSnapshot>(
      stream: _userDocStream,
      builder: (context, snapshot) {
        // Still loading first snapshot
        if (!snapshot.hasData &&
            snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: VivordoTheme.brand),
            ),
          );
        }

        // Firestore error — show message with back button so user isn't stuck
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: Colors.grey, size: 40),
                  const SizedBox(height: 12),
                  const Text('Could not load profile'),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Go back'),
                  ),
                ],
              ),
            ),
          );
        }

        // Doc missing — auto-create it and wait for the stream to update
        final authUser = FirebaseAuth.instance.currentUser;
        if (!snapshot.hasData || !snapshot.data!.exists) {
          if (authUser != null) UserService.createUser(authUser);
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: VivordoTheme.brand),
            ),
          );
        }

        // Extract everything from the ONE snapshot — no extra Firestore listeners.
        final rawData = snapshot.data!.data() as Map<String, dynamic>;
        final userData = UserModel.fromMap(rawData, snapshot.data!.id);
        final pendingEmail = rawData['pendingEmail'] as String?;
        final preferences = rawData['preferences'] as Map? ?? {};
        // A stored null means the person answered "It varies".
        final dayWrapUpVaries =
            preferences.containsKey('dayWrapUpMinutes') &&
            preferences['dayWrapUpMinutes'] == null;
        final dayWrapUp =
            (preferences['dayWrapUpMinutes'] as num?)?.toInt() ??
            kDefaultDayWrapUpMinutes;
        final scanReminderEnabled = preferences['scanReminderEnabled'] != false;
        final checkInReminderEnabled =
            preferences['checkInReminderEnabled'] != false;
        final windDownReminder = preferences['windDownReminder'] == true;
        final checkInMorningReminder =
            preferences['checkInMorningReminder'] == true;
        // Server pushes: on unless switched off.
        final burnoutNotificationsEnabled =
            preferences['burnoutNotificationsEnabled'] != false;
        final achievementNotificationsEnabled =
            preferences['achievementNotificationsEnabled'] != false;
        final circleNotificationsEnabled =
            preferences['circleNotificationsEnabled'] != false;
        final fitnessNotificationsEnabled =
            preferences['fitnessNotificationsEnabled'] != false;
        final savedReminderTimes =
            (preferences['scanReminderTimes'] as List?)
                ?.whereType<num>()
                .map((value) => value.toInt().clamp(0, 1439).toInt())
                .toSet()
                .toList() ??
            [];
        final scanReminderTimes = savedReminderTimes.isNotEmpty
            ? savedReminderTimes
            : <int>[
                ((preferences['scanReminderMorningMinutes'] as num?)?.toInt() ??
                        9 * 60)
                    .clamp(0, 1439)
                    .toInt(),
                ((preferences['scanReminderEveningMinutes'] as num?)?.toInt() ??
                        17 * 60)
                    .clamp(0, 1439)
                    .toInt(),
              ];
        scanReminderTimes.sort();

        final selectedMetricCount = _selectedHealthMetrics(rawData);
        final fitbitConnected = rawData['fitbitConnected'] == true;
        final whoopConnected = rawData['whoopConnected'] == true;
        final dark = Theme.of(context).brightness == Brightness.dark;

        return Scaffold(
          backgroundColor: context.vivordoColors.page,
          body: SafeArea(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
              children: [
                const _SettingsHeader('Settings'),
                _profileCard(userData),
                if (pendingEmail != null) ...[
                  const SizedBox(height: 10),
                  _pendingEmailBanner(pendingEmail),
                ],

                const _SectionLabel('Connections'),
                _SettingsCard(
                  children: [
                    _SettingsRow(
                      leading: const _IconBadge(Icons.favorite_rounded, _red),
                      title: 'Apple Health',
                      status: (
                        selectedMetricCount > 0,
                        selectedMetricCount > 0
                            ? '$selectedMetricCount of ${kHealthMetrics.length} metrics'
                            : 'Off',
                      ),
                      trailing: const _Chevron(),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const _AppleHealthSettingsPage(),
                        ),
                      ),
                    ),
                    _connectionRow(
                      leading: _IconBadge.custom(
                        color: dark ? Colors.white : Colors.black,
                        child: SvgPicture.asset(
                          dark
                              ? 'assets/whoop_puck_white.svg'
                              : 'assets/whoop_puck_black.svg',
                          width: 24,
                          height: 24,
                          excludeFromSemantics: true,
                        ),
                      ),
                      name: 'WHOOP',
                      connected: whoopConnected,
                      busy: _isUpdatingWhoop,
                      onConnect: () => _updateWhoopConnection(false),
                      onSync: _syncWhoop,
                      onDisconnect: () => _updateWhoopConnection(true),
                    ),
                    _connectionRow(
                      leading: const _IconBadge(
                        Icons.watch_rounded,
                        Color(0xFF00B0B9),
                      ),
                      name: 'Fitbit',
                      connected: fitbitConnected,
                      busy: _isUpdatingFitbit,
                      onConnect: () => _updateFitbitConnection(false),
                      onSync: _syncFitbit,
                      onDisconnect: () => _updateFitbitConnection(true),
                    ),
                    _connectionRow(
                      leading: const _IconBadge(
                        Icons.calendar_month_rounded,
                        Color(0xFF4285F4),
                      ),
                      name: 'Google Calendar',
                      connected: _isGoogleCalendarConnected,
                      busy: _isUpdatingGoogleCalendar,
                      onConnect: _updateGoogleCalendarConnection,
                      onDisconnect: _updateGoogleCalendarConnection,
                    ),
                    if (OutlookCalendarService.enabled)
                      _connectionRow(
                        leading: const _IconBadge(
                          Icons.calendar_month_rounded,
                          Color(0xFF0078D4),
                        ),
                        name: 'Outlook Calendar',
                        connected: _isOutlookCalendarConnected,
                        busy: _isUpdatingOutlookCalendar,
                        onConnect: _updateOutlookCalendarConnection,
                        onDisconnect: _updateOutlookCalendarConnection,
                      ),
                  ],
                ),

                const _SectionLabel('Notifications'),
                _SettingsCard(
                  children: [
                    Column(
                      children: [
                        _SettingsRow(
                          leading: const _IconBadge(
                            Icons.monitor_heart_outlined,
                            VivordoTheme.brand,
                          ),
                          title: 'Scan reminders',
                          subtitle:
                              '${scanReminderTimes.length} '
                              '${scanReminderTimes.length == 1 ? 'reminder' : 'reminders'} '
                              'each day',
                          trailing: _SettingsSwitch(
                            value: scanReminderEnabled,
                            onChanged: (value) => _updateReminderPreference(
                              field: 'scanReminderEnabled',
                              enabled: value,
                            ),
                          ),
                        ),
                        if (scanReminderEnabled)
                          _reminderChips(scanReminderTimes),
                      ],
                    ),
                    _SettingsRow(
                      leading: const _IconBadge(
                        Icons.chat_bubble_outline_rounded,
                        _green,
                      ),
                      title: 'End-of-day check-in',
                      subtitle: 'After your final calendar event',
                      trailing: _SettingsSwitch(
                        value: checkInReminderEnabled,
                        onChanged: (value) => _updateReminderPreference(
                          field: 'checkInReminderEnabled',
                          enabled: value,
                        ),
                      ),
                    ),
                    _SettingsRow(
                      leading: const _IconBadge(
                        Icons.bedtime_outlined,
                        VivordoTheme.brand,
                      ),
                      title: 'Wind-down reminder',
                      subtitle: 'An hour before bed, moving with your forecast',
                      trailing: _SettingsSwitch(
                        value: windDownReminder,
                        onChanged: _setWindDownReminder,
                      ),
                    ),
                    _SettingsRow(
                      leading: const _IconBadge(
                        Icons.wb_sunny_outlined,
                        Color(0xFFEF9F27),
                      ),
                      title: 'Morning check-in reminder',
                      subtitle: "10 AM, if today's check-in is still open",
                      trailing: _SettingsSwitch(
                        value: checkInMorningReminder,
                        onChanged: (value) => _setPreferenceWith(
                          () => CheckInReminders.setEnabled(value),
                        ),
                      ),
                    ),
                    _SettingsRow(
                      leading: const _IconBadge(
                        Icons.monitor_heart_outlined,
                        Color(0xFFE24B4A),
                      ),
                      title: 'Burnout check',
                      subtitle: 'Only when a warning starts',
                      trailing: _SettingsSwitch(
                        value: burnoutNotificationsEnabled,
                        onChanged: (value) => _setPreferenceWith(
                          () => _setPreference(
                            'burnoutNotificationsEnabled',
                            value,
                          ),
                        ),
                      ),
                    ),
                    _SettingsRow(
                      leading: const _IconBadge(
                        Icons.emoji_events_outlined,
                        Color(0xFFBA7517),
                      ),
                      title: 'Achievements',
                      subtitle: 'When you earn one',
                      trailing: _SettingsSwitch(
                        value: achievementNotificationsEnabled,
                        onChanged: (value) => _setPreferenceWith(
                          () => _setPreference(
                            'achievementNotificationsEnabled',
                            value,
                          ),
                        ),
                      ),
                    ),
                    _SettingsRow(
                      leading: const _IconBadge(Icons.group_outlined, _orange),
                      title: 'Circle',
                      subtitle:
                          'Likes, comments, friend requests and challenges',
                      trailing: _SettingsSwitch(
                        value: circleNotificationsEnabled,
                        onChanged: (value) => _updateReminderPreference(
                          field: 'circleNotificationsEnabled',
                          enabled: value,
                        ),
                      ),
                    ),
                    _SettingsRow(
                      leading: const _IconBadge(
                        Icons.fitness_center_rounded,
                        Color(0xFFFB923C),
                      ),
                      title: 'Fitness',
                      subtitle: 'Goal and fitness ring updates',
                      trailing: _SettingsSwitch(
                        value: fitnessNotificationsEnabled,
                        onChanged: (value) => _updateReminderPreference(
                          field: 'fitnessNotificationsEnabled',
                          enabled: value,
                        ),
                      ),
                    ),
                  ],
                ),

                const _SectionLabel('Preferences'),
                _SettingsCard(
                  children: [
                    const _SettingsRow(
                      leading: _IconBadge(
                        Icons.brightness_6_rounded,
                        VivordoTheme.brand,
                      ),
                      title: 'Appearance',
                      trailing: _AppearanceToggle(),
                    ),
                    _SettingsRow(
                      leading: const _IconBadge(
                        Icons.wb_twilight_rounded,
                        VivordoTheme.brand,
                      ),
                      title: 'End of day',
                      subtitle: 'Plans after this count as your own time',
                      trailing: _ValueChevron(
                        dayWrapUpVaries
                            ? 'It varies'
                            : _formatReminderTime(dayWrapUp),
                      ),
                      onTap: () => _chooseDayWrapUp(dayWrapUp),
                    ),
                  ],
                ),

                const _SectionLabel('Privacy'),
                _SettingsCard(
                  children: [
                    _SettingsRow(
                      leading: const _IconBadge.muted(Icons.block_rounded),
                      title: 'Blocked users',
                      trailing: const _Chevron(),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const BlockedUsersScreen(),
                        ),
                      ),
                    ),
                    _SettingsRow(
                      leading: const _IconBadge.muted(
                        Icons.auto_awesome_rounded,
                      ),
                      title: 'Vivordo AI consent',
                      subtitle:
                          'Ask again before Vivordo AI sends anything to '
                          'Anthropic from this device. Existing insights are '
                          'kept.',
                      trailing: _PillButton(
                        'Reset',
                        tonal: true,
                        onPressed: _resetAiConsent,
                      ),
                    ),
                    _SettingsRow(
                      leading: const _IconBadge.muted(
                        Icons.privacy_tip_outlined,
                      ),
                      title: 'Privacy Policy',
                      trailing: const _ExternalLink(),
                      onTap: () => openVivordoLink(
                        context,
                        Uri.parse(vivordoPrivacyUrl),
                      ),
                    ),
                    _SettingsRow(
                      leading: const _IconBadge.muted(
                        Icons.description_outlined,
                      ),
                      title: 'Terms & Conditions',
                      trailing: const _ExternalLink(),
                      onTap: () =>
                          openVivordoLink(context, Uri.parse(vivordoTermsUrl)),
                    ),
                  ],
                ),

                const _SectionLabel('Support'),
                _SettingsCard(
                  children: [
                    _SettingsRow(
                      leading: const _IconBadge(
                        Icons.bug_report_outlined,
                        _red,
                      ),
                      title: 'Report a bug',
                      subtitle: 'Tell us what went wrong',
                      trailing: const _Chevron(),
                      onTap: _showBugReportSheet,
                    ),
                    _SettingsRow(
                      leading: const _IconBadge(
                        Icons.support_agent_rounded,
                        VivordoTheme.brand,
                      ),
                      title: 'Contact support',
                      subtitle: vivordoSupportEmail,
                      trailing: const _ExternalLink(),
                      onTap: () => openVivordoLink(
                        context,
                        Uri(scheme: 'mailto', path: vivordoSupportEmail),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 26),
                _SettingsCard(
                  children: [
                    InkWell(
                      onTap: () async {
                        // Log while still authenticated — Firestore rules
                        // reject writes once signOut() clears the session.
                        await AnalyticsService().logLogout();
                        await FirebaseAuth.instance.signOut();
                      },
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: Text(
                            'Log out',
                            style: TextStyle(
                              color: VivordoTheme.brand,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: _isDeletingAccount ? null : _deleteAccount,
                    style: TextButton.styleFrom(
                      foregroundColor: _red,
                      textStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isDeletingAccount) ...[
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _red,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          _isDeletingAccount
                              ? 'Deleting account…'
                              : 'Delete account',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _profileCard(UserModel user) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final name = user.displayName?.trim() ?? '';
    final photoUrl = user.photoUrl;
    final fallback = name.isEmpty
        ? const Icon(
            Icons.person_outline_rounded,
            color: Colors.white,
            size: 26,
          )
        : Text(
            name[0].toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        // The Home stress card's gradient, so the two heroes match.
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const [Color(0xFF4327EC), Color(0xFF282078), Color(0xFF181445)]
              : const [Color(0xFF8D78F4), Color(0xFF7664DC), Color(0xFF6054BE)],
          stops: const [0, 0.58, 1],
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .18),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: .35),
                width: 2,
              ),
            ),
            child: photoUrl != null && photoUrl.startsWith('http')
                ? ClipOval(
                    child: Image.network(
                      photoUrl,
                      width: 52,
                      height: 52,
                      fit: BoxFit.cover,
                      cacheWidth: 156,
                      cacheHeight: 156,
                      errorBuilder: (_, _, _) => fallback,
                    ),
                  )
                : fallback,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? 'Set your name' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  user.email ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .82),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton(
            onPressed: () => _showAccountSheet(user),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Colors.white.withValues(alpha: .16),
              side: BorderSide(color: Colors.white.withValues(alpha: .24)),
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: const Text('Edit'),
          ),
        ],
      ),
    );
  }

  Widget _pendingEmailBanner(String pendingEmail) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: _orange.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      children: [
        const Icon(Icons.mail_outline_rounded, color: _orange, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Verify your new email: $pendingEmail\n'
            'Check your inbox and tap the link.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              fontWeight: FontWeight.w500,
              color: context.vivordoColors.textPrimary,
            ),
          ),
        ),
      ],
    ),
  );

  /// Name, email and password, each opening its existing edit dialog.
  Future<void> _showAccountSheet(UserModel user) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: context.vivordoColors.page,
    builder: (sheetContext) {
      void edit(String field, String current) {
        Navigator.pop(sheetContext);
        _showEditDialog(context, field, current);
      }

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Account',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: sheetContext.vivordoColors.textPrimary,
                ),
              ),
              const SizedBox(height: 14),
              _SettingsCard(
                children: [
                  _SettingsRow(
                    leading: const _IconBadge(
                      Icons.person_outline_rounded,
                      VivordoTheme.brand,
                    ),
                    title: 'Name',
                    subtitle: user.displayName ?? 'Set your name',
                    trailing: const _Chevron(),
                    onTap: () => edit('Name', user.displayName ?? ''),
                  ),
                  _SettingsRow(
                    leading: const _IconBadge(
                      Icons.mail_outline_rounded,
                      VivordoTheme.brand,
                    ),
                    title: 'Email',
                    subtitle: user.email ?? 'Set your email',
                    trailing: const _Chevron(),
                    onTap: () => edit('Email', user.email ?? ''),
                  ),
                  _SettingsRow(
                    leading: const _IconBadge(
                      Icons.lock_outline_rounded,
                      VivordoTheme.brand,
                    ),
                    title: 'Password',
                    subtitle: '••••••••',
                    trailing: const _Chevron(),
                    onTap: () => edit('Password', ''),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );

  /// A wearable or calendar row. Connected rows open their actions; others
  /// connect in place.
  Widget _connectionRow({
    required Widget leading,
    required String name,
    required bool connected,
    required bool busy,
    required VoidCallback onConnect,
    required VoidCallback onDisconnect,
    VoidCallback? onSync,
  }) => _SettingsRow(
    leading: leading,
    title: name,
    status: (
      connected,
      busy
          ? (connected ? 'Updating…' : 'Connecting…')
          : connected
          ? 'Connected'
          : 'Not connected',
    ),
    trailing: busy
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: VivordoTheme.brand,
            ),
          )
        : connected
        ? const _Chevron()
        : _PillButton('Connect', onPressed: onConnect),
    onTap: busy
        ? null
        : connected
        ? () => _showConnectionActions(
            name: name,
            onSync: onSync,
            onDisconnect: onDisconnect,
          )
        : onConnect,
  );

  Future<void> _showConnectionActions({
    required String name,
    required VoidCallback onDisconnect,
    VoidCallback? onSync,
  }) async {
    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: Text(name),
        message: const Text('Connected'),
        actions: [
          if (onSync != null)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(sheetContext, 'sync'),
              child: const Text('Sync last 30 days'),
            ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(sheetContext, 'disconnect'),
            child: const Text('Disconnect'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetContext),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'sync':
        onSync?.call();
      case 'disconnect':
        onDisconnect();
    }
  }

  Widget _reminderChips(List<int> reminderTimes) => Padding(
    padding: const EdgeInsets.fromLTRB(60, 0, 14, 14),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (var index = 0; index < reminderTimes.length; index++)
            _TimeChip(
              _formatReminderTime(reminderTimes[index]),
              semanticsLabel:
                  'Scan reminder at ${_formatReminderTime(reminderTimes[index])}',
              onTap: () => _showReminderTimeActions(reminderTimes, index),
            ),
          if (reminderTimes.length < 10)
            _TimeChip(
              '+ Add',
              accent: true,
              semanticsLabel: 'Add a scan reminder',
              onTap: () =>
                  _chooseScanReminderTime(reminderTimes: reminderTimes),
            ),
        ],
      ),
    ),
  );

  /// Change or remove one reminder. At least one reminder must stay.
  Future<void> _showReminderTimeActions(
    List<int> reminderTimes,
    int index,
  ) async {
    if (reminderTimes.length <= 1) {
      return _chooseScanReminderTime(
        reminderTimes: reminderTimes,
        index: index,
      );
    }
    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: Text(
          'Scan reminder at ${_formatReminderTime(reminderTimes[index])}',
        ),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(sheetContext, 'change'),
            child: const Text('Change time'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(sheetContext, 'remove'),
            child: const Text('Remove reminder'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetContext),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'change':
        await _chooseScanReminderTime(
          reminderTimes: reminderTimes,
          index: index,
        );
      case 'remove':
        await _removeScanReminderTime(reminderTimes, index);
    }
  }

  Future<void> _showBugReportSheet() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: context.vivordoColors.page,
    builder: (sheetContext) {
      var sending = false;
      return StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final colors = sheetContext.vivordoColors;
          return Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              20 + MediaQuery.viewInsetsOf(sheetContext).bottom,
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Report a bug',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tell us what went wrong and we’ll look into it.',
                    style: TextStyle(fontSize: 13, color: colors.textSecondary),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _bugReportController,
                    autofocus: true,
                    minLines: 4,
                    maxLines: 8,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'Describe the bug…',
                      contentPadding: EdgeInsets.all(14),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _bugReportController,
                    builder: (context, value, _) => FilledButton(
                      onPressed: sending || value.text.trim().isEmpty
                          ? null
                          : () async {
                              setSheetState(() => sending = true);
                              final sent = await _submitBugReport();
                              if (sent && sheetContext.mounted) {
                                Navigator.pop(sheetContext);
                              } else if (sheetContext.mounted) {
                                setSheetState(() => sending = false);
                              }
                            },
                      style: FilledButton.styleFrom(
                        backgroundColor: VivordoTheme.brand,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      child: Text(sending ? 'Sending…' : 'Send report'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

/// Apple Health metrics the person has allowed, from their user document.
Map<String, bool> _healthConsent(Map<String, dynamic> userData) =>
    (userData['healthKitConsent'] as Map? ?? {}).map(
      (key, value) => MapEntry(key.toString(), value == true),
    );

int _selectedHealthMetrics(Map<String, dynamic> userData) {
  final consent = _healthConsent(userData);
  return kHealthMetrics.where((metric) => consent[metric.key] == true).length;
}

/// Which Apple Health metrics Vivordo syncs, one switch each.
class _AppleHealthSettingsPage extends StatefulWidget {
  const _AppleHealthSettingsPage();

  @override
  State<_AppleHealthSettingsPage> createState() =>
      _AppleHealthSettingsPageState();
}

class _AppleHealthSettingsPageState extends State<_AppleHealthSettingsPage> {
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _userDocStream;
  bool _isConnectingAll = false;
  String? _togglingMetric;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    _userDocStream = uid == null
        ? const Stream.empty()
        : FirebaseFirestore.instance.collection('users').doc(uid).snapshots();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _enableAll() async {
    setState(() => _isConnectingAll = true);
    try {
      final granted = await HealthService().enableAll();
      if (!granted) _showMessage('Apple Health permissions were not granted.');
    } catch (e) {
      _showMessage('Could not connect: $e');
    } finally {
      if (mounted) setState(() => _isConnectingAll = false);
    }
  }

  Future<void> _toggleMetric(HealthMetricDef metric, bool enable) async {
    if (_togglingMetric != null) return;
    setState(() => _togglingMetric = metric.key);
    try {
      if (enable) {
        final granted = await HealthService().enableMetric(metric.key);
        if (!granted) {
          _showMessage(
            '${metric.label} was not enabled. Review Vivordo permissions in '
            'Apple Health.',
          );
        }
      } else {
        await HealthService().disableMetric(metric.key);
      }
    } catch (e) {
      _showMessage('Error: $e');
    } finally {
      if (mounted) setState(() => _togglingMetric = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _userDocStream,
      builder: (context, snapshot) {
        final data = snapshot.data?.data() ?? const <String, dynamic>{};
        final consent = _healthConsent(data);
        final selected = _selectedHealthMetrics(data);
        final allOn = selected == kHealthMetrics.length;
        return Scaffold(
          backgroundColor: colors.page,
          body: SafeArea(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 60),
              children: [
                const _SettingsHeader('Apple Health'),
                _SettingsCard(
                  children: [
                    _SettingsRow(
                      leading: const _IconBadge(
                        Icons.favorite_rounded,
                        _SettingsScreenState._red,
                      ),
                      title: 'Health data sync',
                      status: (
                        selected > 0,
                        selected > 0
                            ? '$selected of ${kHealthMetrics.length} metrics'
                            : 'No metrics selected',
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
                  child: Text(
                    'Apple controls access. Vivordo only reads the metrics you '
                    'approve. Turning a metric off removes its saved data from '
                    'Vivordo but does not change Apple Health permissions.',
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                _SectionLabel(
                  'Metrics',
                  trailing: allOn
                      ? null
                      : _isConnectingAll
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: VivordoTheme.brand,
                          ),
                        )
                      : TextButton(
                          onPressed: _enableAll,
                          style: TextButton.styleFrom(
                            foregroundColor: VivordoTheme.brand,
                            minimumSize: const Size(0, 32),
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            textStyle: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          child: const Text('Turn all on'),
                        ),
                ),
                _SettingsCard(
                  children: [
                    for (final metric in kHealthMetrics)
                      _metricRow(metric, enabled: consent[metric.key] == true),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _metricRow(HealthMetricDef metric, {required bool enabled}) {
    final toggling = _togglingMetric == metric.key;
    return _SettingsRow(
      leading: _IconBadge(
        _metricIcon(metric.key),
        enabled ? VivordoTheme.brand : context.vivordoColors.textSecondary,
      ),
      title: metric.label,
      subtitle: toggling
          ? (enabled
                ? 'Removing saved Vivordo data…'
                : 'Requesting Apple Health access…')
          : metric.description,
      trailing: toggling
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: VivordoTheme.brand,
              ),
            )
          : _SettingsSwitch(
              value: enabled,
              onChanged: _togglingMetric == null
                  ? (value) => _toggleMetric(metric, value)
                  : null,
            ),
    );
  }
}

IconData _metricIcon(String key) => switch (key) {
  'steps' => Icons.directions_walk_rounded,
  'active_calories' => Icons.local_fire_department_rounded,
  'exercise_time' => Icons.fitness_center_rounded,
  'distance' => Icons.straighten_rounded,
  'heart_rate' => Icons.favorite_rounded,
  'resting_heart_rate' => Icons.favorite_border_rounded,
  'hrv' => Icons.show_chart_rounded,
  'blood_oxygen' => Icons.air_rounded,
  'respiratory_rate' => Icons.wind_power_rounded,
  'sleep' => Icons.bedtime_rounded,
  'weight' => Icons.monitor_weight_rounded,
  'body_fat' => Icons.percent_rounded,
  'vo2max' => Icons.speed_rounded,
  _ => Icons.monitor_heart_outlined,
};

// ── Shared settings pieces ──────────────────────────────────────────────────

class _SettingsHeader extends StatelessWidget {
  const _SettingsHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 18),
      child: Row(
        children: [
          Material(
            color: colors.card,
            shape: CircleBorder(side: BorderSide(color: colors.border)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => Navigator.maybePop(context),
              child: SizedBox(
                width: 40,
                height: 40,
                child: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 16,
                  color: colors.textPrimary,
                  semanticLabel: 'Back',
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                color: colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 24, 0, 8),
    child: SizedBox(
      height: 32,
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.3,
                color: context.vivordoColors.textSecondary,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    ),
  );
}

/// Rows on one card with dividers between them, in My Day's card style.
class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
    color: context.vivordoColors.card,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(color: Colors.black.withValues(alpha: .07)),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0)
            Divider(
              height: 1,
              thickness: 1,
              color: context.vivordoColors.border,
            ),
          children[i],
        ],
      ],
    ),
  );
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.leading,
    required this.title,
    this.subtitle,
    this.status,
    this.trailing,
    this.onTap,
  });

  final Widget leading;
  final String title;
  final String? subtitle;

  /// A connected (green) or idle (grey) dot with its label.
  final (bool, String)? status;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final status = this.status;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 60),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    if (subtitle case final subtitle?) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                    if (status != null) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: status.$1
                                  ? _SettingsScreenState._green
                                  : colors.border,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              status.$2,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: colors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing case final trailing?) ...[
                const SizedBox(width: 10),
                trailing,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge(IconData this.icon, Color this.color) : child = null;

  const _IconBadge.muted(IconData this.icon) : color = null, child = null;

  const _IconBadge.custom({required Color this.color, required this.child})
    : icon = null;

  final IconData? icon;
  final Color? color;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final tint = color ?? colors.textSecondary;
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color == null ? colors.cardMuted : tint.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(11),
      ),
      child: child ?? Icon(icon, size: 18, color: tint),
    );
  }
}

class _SettingsSwitch extends StatelessWidget {
  const _SettingsSwitch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => Switch.adaptive(
    value: value,
    onChanged: onChanged,
    activeTrackColor: VivordoTheme.brand,
  );
}

class _PillButton extends StatelessWidget {
  const _PillButton(this.label, {required this.onPressed, this.tonal = false});

  final String label;
  final VoidCallback onPressed;
  final bool tonal;

  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: onPressed,
    style: FilledButton.styleFrom(
      backgroundColor: tonal
          ? VivordoTheme.brand.withValues(alpha: .12)
          : VivordoTheme.brand,
      foregroundColor: tonal ? VivordoTheme.brand : Colors.white,
      minimumSize: const Size(0, 34),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
    ),
    child: Text(label),
  );
}

class _Chevron extends StatelessWidget {
  const _Chevron();

  @override
  Widget build(BuildContext context) => Icon(
    Icons.chevron_right_rounded,
    color: context.vivordoColors.textSecondary,
  );
}

class _ExternalLink extends StatelessWidget {
  const _ExternalLink();

  @override
  Widget build(BuildContext context) => Icon(
    Icons.open_in_new_rounded,
    size: 18,
    color: context.vivordoColors.textSecondary,
  );
}

class _ValueChevron extends StatelessWidget {
  const _ValueChevron(this.value);

  final String value;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        value,
        style: TextStyle(
          fontSize: 14,
          color: context.vivordoColors.textSecondary,
        ),
      ),
      const _Chevron(),
    ],
  );
}

class _TimeChip extends StatelessWidget {
  const _TimeChip(
    this.label, {
    required this.onTap,
    required this.semanticsLabel,
    this.accent = false,
  });

  final String label;
  final VoidCallback onTap;
  final String semanticsLabel;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return Semantics(
      button: true,
      label: semanticsLabel,
      excludeSemantics: true,
      child: Material(
        color: accent
            ? VivordoTheme.brand.withValues(alpha: .12)
            : colors.cardMuted,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: accent ? VivordoTheme.brand : colors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// System, Light or Dark, saved to the person's profile.
class _AppearanceToggle extends StatelessWidget {
  const _AppearanceToggle();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ThemeController>();
    final colors = context.vivordoColors;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: colors.input,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (mode, label) in const [
            (ThemeMode.system, 'System'),
            (ThemeMode.light, 'Light'),
            (ThemeMode.dark, 'Dark'),
          ])
            Semantics(
              button: true,
              selected: controller.mode == mode,
              label: '$label appearance',
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => controller.setMode(mode),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: controller.mode == mode
                        ? VivordoTheme.brand
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: controller.mode == mode
                          ? Colors.white
                          : colors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AccountDeletionConfirmation {
  const _AccountDeletionConfirmation({this.password});

  final String? password;
}

class SlideToDelete extends StatefulWidget {
  const SlideToDelete({
    required this.enabled,
    required this.onConfirmed,
    super.key,
  });

  final bool enabled;
  final VoidCallback onConfirmed;

  @override
  State<SlideToDelete> createState() => _SlideToDeleteState();
}

class _SlideToDeleteState extends State<SlideToDelete> {
  static const _confirmThreshold = 0.92;
  static const _height = 56.0;
  static const _thumbSize = 48.0;
  static const _inset = 4.0;
  final GlobalKey _trackKey = GlobalKey();
  double _position = 0;
  bool _dragging = false;
  bool _confirmed = false;

  void _setPosition(double value) {
    if (!widget.enabled || _confirmed) return;
    final next = value.clamp(0.0, 1.0);
    setState(() => _position = next);
  }

  void _increaseForAccessibility() {
    final next = (_position + 0.25).clamp(0.0, 1.0);
    if (next >= _confirmThreshold) {
      _confirm();
    } else {
      _setPosition(next);
    }
  }

  void _updateFromDrag(DragUpdateDetails details) {
    final renderBox =
        _trackKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final travel = renderBox.size.width - _thumbSize - _inset * 2;
    if (travel <= 0) return;
    _setPosition(_position + details.delta.dx / travel);
  }

  void _confirm() {
    if (_confirmed) return;
    setState(() {
      _confirmed = true;
      _dragging = false;
      _position = 1;
    });
    widget.onConfirmed();
  }

  void _reset() {
    if (_confirmed) return;
    setState(() {
      _dragging = false;
      _position = 0;
    });
  }

  @override
  void didUpdateWidget(covariant SlideToDelete oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && oldWidget.enabled) _reset();
  }

  @override
  Widget build(BuildContext context) {
    final disabledColor = Theme.of(context).disabledColor;
    const destructiveColor = Color(0xFFFF3B30);
    return Semantics(
      slider: true,
      enabled: widget.enabled,
      label: 'Slide to permanently delete account',
      value: '${(_position * 100).round()} percent',
      increasedValue: widget.enabled ? 'Move toward delete' : null,
      decreasedValue: widget.enabled ? 'Move away from delete' : null,
      onIncrease: widget.enabled ? _increaseForAccessibility : null,
      onDecrease: widget.enabled ? () => _setPosition(_position - 0.25) : null,
      child: GestureDetector(
        key: _trackKey,
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: widget.enabled
            ? (_) => setState(() => _dragging = true)
            : null,
        onHorizontalDragUpdate: widget.enabled ? _updateFromDrag : null,
        onHorizontalDragEnd: widget.enabled
            ? (_) {
                if (_position >= _confirmThreshold) {
                  _confirm();
                } else {
                  _reset();
                }
              }
            : null,
        onHorizontalDragCancel: widget.enabled ? _reset : null,
        child: SizedBox(
          height: _height,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: widget.enabled
                        ? destructiveColor.withValues(alpha: 0.10)
                        : disabledColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(_height / 2),
                    border: Border.all(
                      color: widget.enabled
                          ? destructiveColor.withValues(alpha: 0.32)
                          : disabledColor.withValues(alpha: 0.20),
                    ),
                  ),
                ),
              ),
              AnimatedOpacity(
                opacity: 1 - (_position * 0.75),
                duration: const Duration(milliseconds: 80),
                child: Padding(
                  padding: EdgeInsets.only(
                    left: widget.enabled ? 12 : _thumbSize + 12,
                    right: 12,
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      widget.enabled ? 'Slide to delete' : 'Enter password',
                      maxLines: 1,
                      style: TextStyle(
                        color: widget.enabled
                            ? destructiveColor
                            : disabledColor,
                        fontSize: widget.enabled ? 14 : 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(_inset),
                  child: AnimatedAlign(
                    duration: _dragging
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment(-1 + 2 * _position, 0),
                    child: Container(
                      width: _thumbSize,
                      height: _thumbSize,
                      decoration: BoxDecoration(
                        color: widget.enabled
                            ? destructiveColor
                            : disabledColor,
                        shape: BoxShape.circle,
                        boxShadow: widget.enabled
                            ? [
                                BoxShadow(
                                  color: destructiveColor.withValues(
                                    alpha: 0.28,
                                  ),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: const Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
