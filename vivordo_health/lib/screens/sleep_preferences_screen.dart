import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/material.dart';

import '../src/services/wind_down_reminder.dart';
import '../src/utils/day_key.dart';
import '../src/utils/sleep_nights.dart';
import '../src/utils/sleep_schedule.dart';
import '../theme/vivordo_theme.dart';
import '../widgets/apple_ui.dart';
import '../widgets/sleep_schedule_editor.dart';

/// Sleep preferences, opened from the Sleep screen: your usual sleep
/// schedule (weekday and weekend times) and the wind-down reminder. Changes
/// save as they're made.
class SleepPreferencesScreen extends StatefulWidget {
  const SleepPreferencesScreen({super.key});

  @override
  State<SleepPreferencesScreen> createState() => _SleepPreferencesScreenState();
}

class _SleepPreferencesScreenState extends State<SleepPreferencesScreen> {
  bool _loading = true;
  SleepSchedule _schedule = SleepSchedule.fallback;

  /// Nothing saved yet: [_schedule] is a suggestion from tracked sleep (or
  /// the 11:30 PM–7 AM starting point) until it's changed.
  bool _suggested = true;
  bool _windDown = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final user = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final preferences = user.data()?['preferences'] as Map?;
      var schedule = SleepSchedule.fromPreferences(preferences);
      final saved = schedule != null;
      if (schedule == null) {
        final today = DateUtils.dateOnly(DateTime.now());
        final days = await user.reference
            .collection('metrics_daily')
            .where(
              FieldPath.documentId,
              isGreaterThan: localDayKey(
                today.subtract(const Duration(days: 14)),
              ),
            )
            .get();
        schedule = SleepSchedule.fromNights(
          sleepNights([for (final day in days.docs) day.data()]),
        );
      }
      if (!mounted) return;
      setState(() {
        _schedule = schedule ?? SleepSchedule.fallback;
        _suggested = !saved;
        _windDown = preferences?['windDownReminder'] == true;
        _loading = false;
      });
    } catch (error) {
      debugPrint('Sleep preferences failed to load: $error');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _changeSchedule(SleepSchedule schedule) async {
    final (previous, wasSuggested) = (_schedule, _suggested);
    setState(() {
      _schedule = schedule;
      _suggested = false;
    });
    try {
      await saveSleepSchedule(schedule);
      // The reminder follows the schedule, so reschedule it.
      if (_windDown) await WindDownReminders.sync();
    } catch (error) {
      debugPrint('Sleep schedule save failed: $error');
      if (!mounted) return;
      setState(() {
        _schedule = previous;
        _suggested = wasSuggested;
      });
      showToast(
        context,
        "Couldn't save your sleep times. Try again.",
        kind: ToastKind.error,
      );
    }
  }

  Future<void> _setWindDown(bool on) async {
    setState(() => _windDown = on);
    try {
      await WindDownReminders.setEnabled(on);
    } catch (error) {
      debugPrint('Wind-down reminder failed: $error');
      if (!mounted) return;
      setState(() => _windDown = !on);
      showToast(
        context,
        "Couldn't change the reminder. Try again.",
        kind: ToastKind.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return Scaffold(
      backgroundColor: colors.page,
      appBar: AppBar(
        backgroundColor: colors.page,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: VivordoTheme.brand,
          ),
        ),
        title: const Text(
          'Sleep preferences',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: _loading
          ? const Center(child: CupertinoActivityIndicator())
          : ListView(
              // Clears the floating Vivordo AI button.
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
              children: [
                _header('Your usual sleep'),
                SleepScheduleEditor(
                  schedule: _schedule,
                  onChanged: _changeSchedule,
                ),
                _footer(
                  '${_suggested ? 'Filled in from your recent sleep. Change anything to save it. ' : ''}'
                  "Sets your energy forecast and wind-down time until Vivordo "
                  "has a week of tracked sleep, and on nights nothing's "
                  "tracked. It's never counted as sleep.",
                ),
                const SizedBox(height: 18),
                _header('Reminders'),
                // Same card as the sleep times above.
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: colors.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colors.border),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: MergeSemantics(
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Wind-down reminder',
                              style: TextStyle(fontSize: 15),
                            ),
                          ),
                          AppSwitch(value: _windDown, onChanged: _setWindDown),
                        ],
                      ),
                    ),
                  ),
                ),
                _footer(
                  'A nudge to start winding down before your usual bedtime. '
                  'It follows your energy forecast each night.',
                ),
              ],
            ),
    );
  }

  Widget _header(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 12,
        letterSpacing: .3,
        color: context.vivordoColors.textSecondary,
      ),
    ),
  );

  Widget _footer(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12,
        height: 1.35,
        color: context.vivordoColors.textSecondary,
      ),
    ),
  );
}
