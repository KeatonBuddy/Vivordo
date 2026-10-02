import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:vivordo_health/src/utils/day_key.dart';

import 'calendar_service.dart';
import 'insight_service.dart';
import 'panda_types.dart';

export 'panda_types.dart';

// =============================================================================
// ARCHITECTURE OVERVIEW
// =============================================================================
//
// Panda runs a HYBRID DIALOGUE MANAGER based on 2025 best practices from
// Rasa, Aisera, and the ICM+LLM literature:
//
//   Predefined path  →  Structured labeling questions generated from spike data.
//                       Questions vary each session (seeded prompting + temp).
//                       User can go as deep as they want per question.
//
//   Undefined path   →  Fully open conversation: advice, tips, venting, etc.
//                       Triggered by intent = "digress" | "advice" | "support"
//
//   Dialogue stack   →  When user digreses mid-predefined-path, the path context
//                       is pushed onto a stack. After the digression is resolved
//                       (intent = "digression_complete"), it is popped and the
//                       predefined path resumes seamlessly.
//
//   Slot filling     →  Every turn, the model extracts wellness entities
//                       (stressor, emotion, intensity, activity, coping_strategy,
//                       etc.) and accumulates them in a slot store.
//
// Everything here is transport-agnostic: Firestore reads, prompt assembly and
// response parsing. ClaudeService supplies the transport.
//
// =============================================================================

// ---------------------------------------------------------------------------
// PandaPrompts
// ---------------------------------------------------------------------------

/// Prompt construction, Firestore payload assembly, and response parsing for
/// the Panda check-in. Holds no transport of its own; ClaudeService calls these
/// to talk to the model.
class PandaPrompts {
  PandaPrompts._();

  static Future<Map<String, dynamic>?> fetchRealUserPayload(
    String userId,
  ) async {
    final db = FirebaseFirestore.instance;
    final now = DateTime.now();
    final userRef = db.collection('users').doc(userId);

    // Each day's metrics live in a single merged doc at
    // users/{userId}/metrics_daily/{YYYY-MM-DD}, keyed by metric type
    // (e.g. 'heart_rate', 'resting_heart_rate', 'hrv', 'steps', 'sleep') — see
    // MetricsService._addMetric, HealthService._writeDataPoints and
    // ScanScreen._saveToFirestore.
    final dateStrings = List.generate(
      7,
      (i) => localDayKey(now.subtract(Duration(days: i))),
    );

    // Fire all Firestore reads concurrently before any await
    final metricFutures = dateStrings
        .map((d) => userRef.collection('metrics_daily').doc(d).get())
        .toList();
    final prefFuture = userRef.collection('preferences').get();
    final questFuture = userRef.collection('questionaire_responses').get();
    // Recurring patterns from past Panda sessions (top-level `insights`).
    // Degrade gracefully if the query fails (e.g. missing composite index) so a
    // first-time user with no insight history never blocks session init.
    final insightsFuture = InsightService(
      firestore: db,
    ).aggregateSummary(userId).catchError((Object _) => <String, dynamic>{});
    // NOTE: Google Calendar is deliberately NOT fetched here. It needs auth +
    // an enumeration of every calendar + a fetch per calendar, which can take
    // seconds — and it sat on the session-init critical path. It is now loaded
    // in the BACKGROUND via fetchScheduleContext() and fed into later dialogue
    // turns, so the chat opens immediately. (Calendar↔spike correlation was
    // near-useless anyway: the metrics are daily aggregates with no real
    // time-of-day, so no event could ever be aligned to a spike.)

    // User root doc — holds analyzed_spike_days (spike-dedupe ledger).
    final userDocFuture = userRef.get();

    final metricSnaps = await Future.wait(metricFutures);
    final prefSnap = await prefFuture;
    final questSnap = await questFuture;
    final insightsAgg = await insightsFuture;
    final userSnap = await userDocFuture;

    // Days whose spike has already been surfaced once — excluded from detection
    // so Panda doesn't re-ask about the same spike.
    final excludedSpikeDays = Set<String>.from(
      (userSnap.data()?['analyzed_spike_days'] as List?)?.whereType<String>() ??
          const <String>[],
    );

    // Build daily data map: dateStr → {field → value} from the single day doc
    final dailyData = <String, Map<String, dynamic>>{};
    for (int i = 0; i < dateStrings.length; i++) {
      final data = metricSnaps[i].data();
      if (data == null) continue;
      dailyData[dateStrings[i]] = data;
    }

    if (dailyData.isEmpty) return null;

    // HR baseline: 7-day average, preferring resting_heart_rate over heart_rate.
    final hrValues = dailyData.values
        .map(
          (d) =>
              (d['resting_heart_rate']?['avg'] as num?)?.toDouble() ??
              (d['heart_rate']?['avg'] as num?)?.toDouble(),
        )
        .whereType<double>()
        .toList();
    final baselineHr = hrValues.isEmpty
        ? 65.0
        : hrValues.reduce((a, b) => a + b) / hrValues.length;

    final hrvValues = dailyData.values
        .map((d) => (d['hrv']?['avg'] as num?)?.toDouble())
        .whereType<double>()
        .toList();
    final baselineHrv = hrvValues.isEmpty
        ? 52.0
        : hrvValues.reduce((a, b) => a + b) / hrvValues.length;

    final sortedDates = dailyData.keys.toList()..sort((a, b) => b.compareTo(a));
    final latestDate = sortedDates.first;
    final latestData = dailyData[latestDate]!;

    final todaySleepHrs =
        (latestData['sleep']?['avg'] as num?)?.toDouble() ?? 0.0;
    final sleepQuality = todaySleepHrs >= 8
        ? 80.0
        : todaySleepHrs >= 7
        ? 65.0
        : todaySleepHrs >= 6
        ? 45.0
        : todaySleepHrs > 0
        ? 25.0
        : 0.0;

    final samplesChronological = sortedDates.reversed
        .where((dateStr) => !excludedSpikeDays.contains(dateStr))
        .map(
          (dateStr) => dailySample(
            dateStr,
            dailyData[dateStr]!,
            baselineHr: baselineHr,
            baselineHrv: baselineHrv,
          ),
        )
        .toList();

    final windowStart = DateTime.parse('${sortedDates.last}T00:00:00');
    final windowEnd = DateTime.parse('${latestDate}T23:59:59');

    // Compact user setup from preferences + questionnaire (scalar values only,
    // max 10 fields) — keeps token overhead under ~100 tokens.
    final userSetup = <String, dynamic>{};
    const metaKeys = {'createdAt', 'updatedAt', 'userId', 'id', 'timestamp'};
    for (final doc in [...prefSnap.docs, ...questSnap.docs]) {
      for (final entry in doc.data().entries) {
        if (userSetup.length >= 10) break;
        if (metaKeys.contains(entry.key)) continue;
        final v = entry.value;
        if (v is String || v is num || v is bool) {
          userSetup[entry.key] = v;
        }
      }
    }

    // Compact cross-session memory from the `insights` aggregate (only non-empty
    // signals) — keeps token overhead to ~30–50 tokens.
    final insightsSummary = <String, dynamic>{};
    if ((insightsAgg['session_count'] as int? ?? 0) > 0) {
      for (final key in const ['top_stressors', 'top_emotions', 'top_coping']) {
        final list =
            (insightsAgg[key] as List?)?.whereType<String>().toList() ?? [];
        if (list.isNotEmpty) insightsSummary[key] = list;
      }
      final intensity = insightsAgg['avg_intensity'] as String?;
      if (intensity != null && intensity.isNotEmpty) {
        insightsSummary['typical_intensity'] = intensity;
      }
      final recentSummaries =
          (insightsAgg['recent_summaries'] as List?)
              ?.whereType<String>()
              .toList() ??
          const [];
      if (recentSummaries.isNotEmpty) {
        insightsSummary['recent_sessions'] = recentSummaries;
      }
      final stressorCounts = insightsAgg['stressor_counts'];
      if (stressorCounts is Map && stressorCounts.isNotEmpty) {
        insightsSummary['stressor_counts'] = stressorCounts;
      }
      insightsSummary['past_session_count'] = insightsAgg['session_count'];
    }

    return {
      'user_profile': {
        'timezone': 'UTC',
        'age_range': 'adult',
        'resting_hr_typical': baselineHr,
        'hrv_rmssd_typical': baselineHrv,
        if (userSetup.isNotEmpty) 'user_setup': userSetup,
        if (insightsSummary.isNotEmpty) 'insights_summary': insightsSummary,
      },
      'data_window': {
        'start': windowStart.toIso8601String(),
        'end': windowEnd.toIso8601String(),
      },
      'samples_5min': samplesChronological,
      // Retained in memory for on-demand conversational metric lookups. This is
      // never embedded wholesale in a model prompt.
      'dashboard_metrics': dailyData,
      // Calendar is loaded in the background (fetchScheduleContext) — it is not
      // on the session-init critical path.
      'events': const <Map<String, dynamic>>[],
      if (todaySleepHrs > 0)
        'sleep_summary': {
          'total_hours': todaySleepHrs,
          'sleep_quality': sleepQuality,
        },
      'user_meta': {'userId': userId, 'hrv': baselineHrv},
    };
  }

  /// One day's spike-detection sample from its metrics_daily doc.
  ///
  /// `hr` is the day's RESTING heart rate (average heart rate when resting is
  /// missing), the same measure the baseline is built from. The day's MAX
  /// heart rate is deliberately ignored: any walk or workout pushes it far
  /// above resting, which made almost every active day look like a spike.
  @visibleForTesting
  static Map<String, dynamic> dailySample(
    String dateStr,
    Map<String, dynamic> d, {
    required double baselineHr,
    required double baselineHrv,
  }) {
    final hr =
        (d['resting_heart_rate']?['avg'] as num?)?.toDouble() ??
        (d['heart_rate']?['avg'] as num?)?.toDouble() ??
        baselineHr;
    final hrv = (d['hrv']?['avg'] as num?)?.toDouble() ?? baselineHrv;
    final steps = (d['steps']?['sum'] as num?)?.toDouble() ?? 0.0;
    final stress = (d['stress']?['avg'] as num?)?.toInt();
    return <String, dynamic>{
      't': '${dateStr}T12:00:00',
      'hr': hr.round(),
      'hrv': hrv.round(),
      'steps': steps.round(),
      'activity': steps > 8000
          ? 'active'
          : steps > 3000
          ? 'light'
          : 'sedentary',
      'stress': ?stress,
      'tag': '',
    };
  }

  /// Graceful empty-state session when the user has no metrics yet.
  static PandaSessionData emptyStateSession(String name) {
    return PandaSessionData(
      openerMessage:
          'Hey $name! 👋 I don\'t have any health data to analyze yet. '
          'Once you start tracking your metrics, I\'ll be able to surface '
          'personalized stress insights here. For now, feel free to chat with '
          'me about anything on your mind.',
      questions: [],
      overallNotes: '',
      rawSpikes: [],
    );
  }

  /// Fetches the Google Calendar schedule digest: the past 3 days and the
  /// next week.
  ///
  /// Runs OFF the session-init critical path — the calendar needs auth, an
  /// enumeration of every calendar, and a fetch per calendar, which can take
  /// seconds. PandaScreen calls this in the background after the chat has
  /// already opened and feeds the result into subsequent dialogue turns.
  /// Returns null when Calendar isn't connected or nothing is scheduled.
  static Future<String?> fetchScheduleContext() async {
    try {
      final now = DateTime.now();
      // The past 3 days too, so "what did I have on Monday?" works.
      final dayStart = DateTime(now.year, now.month, now.day - 3);
      final events = await CalendarService.getEventsBetween(
        dayStart,
        dayStart.add(const Duration(days: _scheduleDays + 1)),
      ).timeout(const Duration(seconds: 12), onTimeout: () => <gcal.Event>[]);
      final digest = _buildScheduleDigest(events, dayStart);
      return digest.isEmpty ? null : digest;
    } catch (e) {
      if (kDebugMode) debugPrint('[schedule] background fetch failed: $e');
      return null;
    }
  }

  /// Immediate session built from the payload alone — NO LLM call.
  ///
  /// [hasSpikes] false → nothing to analyze (chat is already final).
  /// [hasSpikes] true  → the opener shows now while the labeling questions are
  /// still being generated in the background (progressive loading).
  static PandaSessionData bootstrapSession(
    Map<String, dynamic> payload, {
    String? overrideName,
    required bool hasSpikes,
  }) {
    final meta = payload['user_meta'] as Map<String, dynamic>?;
    final userName = overrideName?.isNotEmpty == true
        ? overrideName!
        : (meta?['userId'] as String? ?? 'there')
              .replaceAll(RegExp(r'[_\-]'), ' ')
              .split(' ')
              .first;

    final sleepSummary = payload['sleep_summary'] as Map?;
    final sleepHours =
        (sleepSummary?['total_hours'] as num?)?.toDouble() ?? 0.0;

    return PandaSessionData(
      openerMessage: _buildWarmOpener(
        userName: userName,
        hasSpikes: hasSpikes,
        overallNotes: '',
        sleepHours: sleepHours,
      ),
      questions: const [],
      overallNotes: '',
      rawSpikes: const [],
      dashboardMetrics: _dashboardMetricsFromPayload(payload),
      insightsContext: _insightsContextFromPayload(payload),
    );
  }

  /// Session for a user who HAS data but no NEW spike to analyze (e.g. every
  /// detected spike day was already surfaced once).
  ///
  /// There is nothing to label, so this skips the spike-analysis LLM call
  /// entirely and opens the chat instantly instead of waiting on a round trip
  /// that would just return `spikes: []`. Schedule + insights context still
  /// travel with it so the dialogue keeps full context.
  static PandaSessionData noSpikesSession(
    Map<String, dynamic> payload, {
    String? overrideName,
  }) => bootstrapSession(payload, overrideName: overrideName, hasSpikes: false);

  // =========================================================================
  // Spike de-duplication  (public static — used by PandaScreen)
  //
  // Spikes are identified by their DAY (metrics are daily aggregates). Once the
  // user answers or skips a question about a day's spike, it is recorded on the
  // user doc so it is never re-detected.
  // =========================================================================

  /// The set of spike days (YYYY-MM-DD) in a list of spike maps.
  static List<String> spikeDays(Iterable<Object?> spikes) {
    return spikes
        .map((s) => (s as Map)['start']?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .map((s) => s.contains('T') ? s.split('T').first : s)
        .toSet()
        .toList();
  }

  /// Records [days] as analyzed on the user doc so their spikes aren't re-asked.
  static Future<void> markSpikeDaysAnalyzed(
    String userId,
    List<String> days,
  ) async {
    if (days.isEmpty) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(userId).set({
        'analyzed_spike_days': FieldValue.arrayUnion(days),
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      if (kDebugMode) debugPrint('[spike-dedupe] mark failed: $e');
    }
  }

  static const _weekdayAbbr = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  static const _monthAbbr = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// Human day label for a spike (e.g. "Wed, Jun 17"). Health metrics are daily
  /// aggregates, so this is the finest real granularity — never a clock time.
  static String _dayPhrase(String? iso) {
    if (iso == null || iso.isEmpty) return 'that day';
    try {
      final d = DateTime.parse(iso).toLocal();
      return '${_weekdayAbbr[d.weekday - 1]}, ${_monthAbbr[d.month - 1]} ${d.day}';
    } catch (_) {
      return 'that day';
    }
  }

  /// Normalised key for de-duplicating chip options — lowercased with emoji and
  /// punctuation stripped, so "Something else 🙋" and "Something else!" collide.
  static String _optionKey(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// True when a normalised option already acts as the "none of these" choice.
  static bool _isEscapeHatch(String key) =>
      key.contains('something else') || key.contains('other');

  /// Strips the time component from an ISO timestamp, leaving the date only.
  static String _dateOnly(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final t = iso.indexOf('T');
    return t == -1 ? iso : iso.substring(0, t);
  }

  static const _scheduleDays = 10; // 3 days back + today + 6 ahead

  /// Builds a per-day schedule digest for [_scheduleDays] days from
  /// [dayStart] (inclusive) in local time, e.g.:
  ///   Mon 2026-06-22: 09:00–10:00 Standup; 14:00–15:30 Project review
  ///   Tue 2026-06-23: (no events)
  /// Each day is listed so free days are explicit. Returns '' when there are
  /// no timed events in the window (nothing useful to plan around).
  static String _buildScheduleDigest(
    List<gcal.Event> events,
    DateTime dayStart,
  ) {
    final windowEnd = dayStart.add(const Duration(days: _scheduleDays));

    // Group timed events by local calendar day.
    final byDay = <String, List<String>>{};
    var hasAny = false;
    for (final e in events) {
      final startDt = e.start?.dateTime;
      if (startDt == null) continue;
      final localStart = startDt.toLocal();
      if (localStart.isBefore(dayStart) || !localStart.isBefore(windowEnd)) {
        continue;
      }
      final dayKey = localDayKey(localStart);
      final startHm =
          '${localStart.hour.toString().padLeft(2, '0')}:'
          '${localStart.minute.toString().padLeft(2, '0')}';
      final endLocal = e.end?.dateTime?.toLocal();
      final endHm = endLocal == null
          ? ''
          : '–${endLocal.hour.toString().padLeft(2, '0')}:'
                '${endLocal.minute.toString().padLeft(2, '0')}';
      final title = (e.summary ?? 'event').trim();
      (byDay[dayKey] ??= []).add(
        '$startHm$endHm ${title.isEmpty ? 'event' : title}',
      );
      hasAny = true;
    }

    if (!hasAny) return '';

    final lines = <String>[];
    for (int i = 0; i < _scheduleDays; i++) {
      final day = dayStart.add(Duration(days: i));
      final key = localDayKey(day);
      final label = '${_weekdayAbbr[day.weekday - 1]} $key';
      final dayEvents = byDay[key];
      lines.add(
        dayEvents == null || dayEvents.isEmpty
            ? '$label: (no events)'
            : '$label: ${dayEvents.join('; ')}',
      );
    }
    return lines.join('\n');
  }

  // =========================================================================
  // Prompt builders  (public static — reused by ClaudeService)
  // =========================================================================

  // =========================================================================
  // Data processing  (public static — reused by ClaudeService)
  // =========================================================================

  /// Builds the compact spike-candidate payload from raw health data.
  static Map<String, dynamic> buildCompactPayload(
    Map<String, dynamic> raw, {
    int topK = 3,
  }) {
    final profile = raw['user_profile'] ?? {};
    final window = raw['data_window'] ?? {};
    final events = (raw['events'] as List? ?? []).cast<Map>();
    final samples = (raw['samples_5min'] as List? ?? []).cast<Map>();
    final baselineHr = (profile['resting_hr_typical'] ?? 62).toDouble();
    final baselineHrv = (profile['hrv_rmssd_typical'] ?? 52).toDouble();

    var spikeCandidates = _detectSpikes(samples, baselineHr, baselineHrv);
    spikeCandidates.sort(
      (a, b) => _severity(
        b,
        baselineHr,
        baselineHrv,
      ).compareTo(_severity(a, baselineHr, baselineHrv)),
    );
    if (spikeCandidates.length > topK) {
      spikeCandidates = spikeCandidates.sublist(0, topK);
    }

    for (final s in spikeCandidates) {
      s['context'] ??= <String, dynamic>{};
      s['context']['nearby_events'] = _eventsNear(
        events: events,
        startIso: s['start'],
        endIso: s['end'],
        minutes: 90,
      );
      s['context']['confidence'] =
          (s['context']['nearby_events'] as List).isEmpty ? 0.55 : 0.75;

      // Health metrics are DAILY aggregates — there is no real time-of-day for
      // a spike. Expose a day label and strip the placeholder clock time from
      // start/end so the model references the day, never a fabricated hour.
      s['day'] = _dayPhrase(s['start']?.toString());
      s['start'] = _dateOnly(s['start']?.toString());
      s['end'] = _dateOnly(s['end']?.toString());
      s['granularity'] = 'daily';
    }

    final userSetup = profile['user_setup'] as Map?;
    final insightsSummary = profile['insights_summary'] as Map?;
    final recentEvents = profile['recent_events'] as List?;
    final upcomingEvents = profile['upcoming_events'] as List?;
    return {
      'user_profile': {
        'timezone': profile['timezone'] ?? 'UTC',
        'age_range': profile['age_range'] ?? 'adult',
        'resting_hr_typical': baselineHr,
        'hrv_rmssd_typical': baselineHrv,
        if (userSetup != null && userSetup.isNotEmpty) 'user_setup': userSetup,
        if (insightsSummary != null && insightsSummary.isNotEmpty)
          'insights_summary': insightsSummary,
        if (recentEvents != null && recentEvents.isNotEmpty)
          'recent_events': recentEvents,
        if (upcomingEvents != null && upcomingEvents.isNotEmpty)
          'upcoming_events': upcomingEvents,
      },
      'data_window': window,
      'user_context': raw['user_context'] ?? '',
      'spike_candidates': spikeCandidates,
    };
  }

  /// Parses raw spike-analysis JSON into a PandaSessionData.
  static PandaSessionData parsePandaSession(
    String raw,
    Map<String, dynamic> rawSample, {
    String? overrideName,
  }) {
    final userMeta = rawSample['user_meta'] as Map<String, dynamic>?;

    final userName = overrideName?.isNotEmpty == true
        ? overrideName!
        : (userMeta?['userId'] as String? ?? 'there')
              .replaceAll(RegExp(r'[_\-]'), ' ')
              .split(' ')
              .first;

    // Schedule + insights travel with the payload — surface them on every
    // return path so each dialogue turn has calendar + past-session context.
    final scheduleContext = rawSample['upcoming_schedule'] as String?;
    final insightsContext = _insightsContextFromPayload(rawSample);
    final dashboardMetrics = _dashboardMetricsFromPayload(rawSample);

    final obj = _extractJson(raw);

    if (obj == null) {
      return _fallbackSession(
        userName,
        'earlier today',
        [],
        scheduleContext: scheduleContext,
        insightsContext: insightsContext,
        dashboardMetrics: dashboardMetrics,
      );
    }

    final overallNotes = (obj['summary']?['overall_notes'] as String? ?? '')
        .trim();

    final spikes = obj['spikes'] as List?;
    final rawSpikes = spikes?.whereType<Map<String, dynamic>>().toList() ?? [];

    final sleepSummary = rawSample['sleep_summary'] as Map?;
    final sleepHours =
        (sleepSummary?['total_hours'] as num?)?.toDouble() ?? 0.0;

    final openerMessage = _buildWarmOpener(
      userName: userName,
      hasSpikes: spikes != null && spikes.isNotEmpty,
      overallNotes: overallNotes,
      sleepHours: sleepHours,
    );

    if (spikes == null || spikes.isEmpty) {
      return PandaSessionData(
        openerMessage: openerMessage,
        questions: [],
        overallNotes: overallNotes,
        rawSpikes: rawSpikes,
        scheduleContext: scheduleContext,
        insightsContext: insightsContext,
        dashboardMetrics: dashboardMetrics,
      );
    }

    final spike = spikes.first as Map<String, dynamic>;
    // Daily data — reference the day, not a fabricated clock time.
    final timePhrase = _dayPhrase(spike['start'] as String?);

    final questions = <PandaQuestion>[];
    final qs = spike['questions'] as List?;

    if (qs != null) {
      for (final q in qs) {
        if (q is! Map) continue;

        final qid = q['question_id']?.toString() ?? 'q_${questions.length + 1}';
        final qp = q['prompt']?.toString() ?? '';
        if (qp.isEmpty) continue;

        // De-dupe options (the model sometimes repeats one) — compare
        // case/emoji/punctuation-insensitively.
        final opts = <String>[];
        final optKeys = <String>{};
        if (q['options'] is List) {
          for (final o in q['options'] as List) {
            final t = o.toString().trim();
            if (t.isEmpty) continue;
            if (optKeys.add(_optionKey(t))) opts.add(t);
          }
        }

        // Only add the escape hatch when the model didn't already supply one.
        // (The old check looked for "other", which "Something else 🙋" does not
        // contain — so it appended a duplicate every time.)
        if (opts.isNotEmpty && !optKeys.any(_isEscapeHatch)) {
          opts.add('Something else');
        }

        final depths = <String>[];
        if (q['depth_prompts'] is List) {
          for (final d in q['depth_prompts'] as List) {
            final t = d.toString().trim();
            if (t.isNotEmpty) depths.add(t);
          }
        }

        questions.add(
          PandaQuestion(
            questionId: qid,
            prompt: qp,
            options: opts,
            depthPrompts: depths,
          ),
        );
      }
    }

    if (questions.isEmpty) {
      return _fallbackSession(
        userName,
        timePhrase,
        rawSpikes,
        notes: overallNotes,
        scheduleContext: scheduleContext,
        insightsContext: insightsContext,
        dashboardMetrics: dashboardMetrics,
      );
    }

    return PandaSessionData(
      openerMessage: openerMessage,
      questions: questions,
      overallNotes: overallNotes,
      rawSpikes: rawSpikes,
      scheduleContext: scheduleContext,
      insightsContext: insightsContext,
      dashboardMetrics: dashboardMetrics,
    );
  }

  static Map<String, Map<String, dynamic>> _dashboardMetricsFromPayload(
    Map<String, dynamic> payload,
  ) {
    final raw = payload['dashboard_metrics'];
    if (raw is! Map) return const {};
    return raw.map(
      (date, metrics) => MapEntry(
        date.toString(),
        metrics is Map
            ? Map<String, dynamic>.from(metrics)
            : <String, dynamic>{},
      ),
    );
  }

  /// Formats the payload's insights_summary into a compact PAST-SESSIONS block
  /// for the dialogue context. Returns null when there is no usable history.
  static String? _insightsContextFromPayload(Map<String, dynamic> rawSample) {
    final profile = rawSample['user_profile'];
    if (profile is! Map) return null;
    final s = profile['insights_summary'];
    if (s is! Map) return null;

    final lines = <String>[];
    List<String> asList(Object? v) =>
        (v as List?)?.whereType<String>().where((e) => e.isNotEmpty).toList() ??
        const [];

    final stressors = asList(s['top_stressors']);
    final emotions = asList(s['top_emotions']);
    final coping = asList(s['top_coping']);
    final intensity = (s['typical_intensity'] as String?)?.trim() ?? '';
    final recents = asList(s['recent_sessions']);
    final counts = s['stressor_counts'] is Map
        ? (s['stressor_counts'] as Map)
        : const {};

    if (stressors.isNotEmpty) {
      // Annotate with frequency so priority is explicit, e.g.
      // "academia (5×), work stress (3×)" — higher count = higher priority,
      // but all listed stressors still matter.
      final rendered = stressors
          .map((st) {
            final c = (counts[st] as num?)?.toInt() ?? 0;
            return c > 1 ? '$st (${c}×)' : st;
          })
          .join(', ');
      lines.add('Recurring stressors (by frequency): $rendered');
    }
    if (emotions.isNotEmpty)
      lines.add('Common emotions: ${emotions.join(', ')}');
    if (coping.isNotEmpty)
      lines.add('Coping that came up: ${coping.join(', ')}');
    if (intensity.isNotEmpty) lines.add('Typical intensity: $intensity');
    if (recents.isNotEmpty) {
      lines.add('Recent session recaps:');
      for (final r in recents) {
        lines.add('• $r');
      }
    }

    if (lines.isEmpty) return null;
    return lines.join('\n');
  }

  /// Parses a raw dialogue-turn JSON string into a PandaTurnReply.
  static PandaTurnReply parseTurnReply(String raw) {
    try {
      final obj = _extractJson(raw);
      if (obj == null) throw FormatException('no JSON');

      final intentStr = obj['intent']?.toString() ?? 'chitchat';
      final intent = _parseIntent(intentStr);
      final message = obj['message']?.toString().trim().isNotEmpty == true
          ? obj['message'].toString().trim()
          : 'Got it';

      final depthFollowUp = (intent == PandaIntent.wantDeeperAnswer)
          ? obj['depth_follow_up']?.toString().trim()
          : null;

      PandaQuestion? injected;
      if (intent == PandaIntent.newStressor) {
        final iqRaw = obj['injected_question'];
        if (iqRaw is Map<String, dynamic>) {
          final qid = iqRaw['question_id']?.toString() ?? '';
          final qp = iqRaw['prompt']?.toString() ?? '';
          final opts = <String>[];
          final optKeys = <String>{};
          if (iqRaw['options'] is List) {
            for (final o in iqRaw['options'] as List) {
              final t = o.toString().trim();
              if (t.isEmpty) continue;
              if (optKeys.add(_optionKey(t))) opts.add(t); // de-dupe
            }
          }
          if (opts.isNotEmpty && !optKeys.any(_isEscapeHatch)) {
            opts.add('Something else');
          }
          if (qid.isNotEmpty && qp.isNotEmpty && opts.isNotEmpty) {
            injected = PandaQuestion(
              questionId: qid,
              prompt: qp,
              options: opts,
            );
          }
        }
      }

      Map<String, String>? slots;
      if (obj['filled_slots'] is Map<String, dynamic>) {
        final rawSlots = obj['filled_slots'] as Map<String, dynamic>;
        final m = <String, String>{};
        rawSlots.forEach((k, v) {
          final val = v?.toString().trim() ?? '';
          if (val.isNotEmpty) m[k] = val;
        });
        if (m.isNotEmpty) slots = m;
      }

      final recHint = (intent == PandaIntent.recommend)
          ? (obj['rec_hint']?.toString().trim().isNotEmpty == true
                ? obj['rec_hint'].toString().trim()
                : null)
          : null;

      final calendarAction =
          intent == PandaIntent.calendarAction && obj['calendar_action'] is Map
          ? calendarActionFrom(obj['calendar_action'] as Map)
          : null;
      final actions = [
        for (final raw in (obj['actions'] as List? ?? const []))
          if (raw is Map && raw['type'] == 'calendar')
            (calendar: calendarActionFrom(raw), priority: null)
          else if (raw is Map && raw['type'] == 'priority')
            (
              calendar: null,
              priority: Map<String, dynamic>.from(raw)..remove('type'),
            ),
      ].where((a) => a.calendar != null || a.priority != null).toList();

      return PandaTurnReply(
        intent: intent,
        message: message,
        offerEndSession: obj['offer_end_session'] == true,
        crisis: obj['crisis'] == true,
        depthFollowUp: depthFollowUp,
        injectedQuestion: injected,
        filledSlots: slots,
        recHint: recHint,
        calendarAction: calendarAction,
        priorityAction:
            intent == PandaIntent.priorityAction &&
                obj['priority_action'] is Map
            ? Map<String, dynamic>.from(obj['priority_action'] as Map)
            : null,
        actions: actions,
      );
    } catch (_) {
      // Never present a partial action as a completed operation. Only salvage
      // explicitly conversational replies, and clearly label them incomplete.
      final message = _salvageMessage(raw);
      final conversational =
          RegExp(r'"intent"\s*:\s*"chitchat"').hasMatch(raw) &&
          !RegExp(r'"(?:calendar_action|priority_action)"\s*:').hasMatch(raw);
      return PandaTurnReply(
        intent: PandaIntent.chitchat,
        message: conversational && message != null
            ? 'Incomplete response — please retry for the full answer. No changes were made.\n\n$message'
            : 'The response was interrupted. No changes were made—please try again.',
      );
    }
  }

  /// A calendar change from its JSON, or null when it's incomplete.
  static PandaCalendarAction? calendarActionFrom(Map raw) {
    final operation = switch (raw['operation']?.toString().toLowerCase()) {
      'create' => PandaCalendarOperation.create,
      'update' => PandaCalendarOperation.update,
      'delete' => PandaCalendarOperation.delete,
      _ => null,
    };
    DateTime? parseDate(String key) {
      final value = raw[key]?.toString().trim();
      return value == null || value.isEmpty ? null : DateTime.tryParse(value);
    }

    final title = raw['title']?.toString().trim();
    final targetTitle = raw['target_title']?.toString().trim();
    final start = parseDate('start');
    final end = parseDate('end');
    final valid =
        operation != null &&
        ((operation == PandaCalendarOperation.create &&
                title?.isNotEmpty == true &&
                start != null &&
                end != null) ||
            (operation != PandaCalendarOperation.create &&
                targetTitle?.isNotEmpty == true));
    if (!valid) return null;
    return PandaCalendarAction(
      operation: operation,
      title: title,
      targetTitle: targetTitle,
      start: start,
      end: end,
      recurrence: raw['recurrence']?.toString().trim() ?? 'none',
    );
  }

  /// Best-effort recovery of the "message" string from truncated JSON.
  static String? _salvageMessage(String raw) {
    final m = RegExp(r'"message"\s*:\s*"((?:[^"\\]|\\.)*)').firstMatch(raw);
    final body = m?.group(1)?.replaceFirst(RegExp(r'\\u[0-9a-fA-F]{0,3}$'), '');
    if (body == null) return null;
    try {
      final text = (jsonDecode('"$body"') as String).trim();
      return text.isEmpty ? null : text;
    } catch (_) {
      return null;
    }
  }

  /// Strips spike objects to (spike_id, window, top_hypothesis) to bound
  /// per-turn prompt token cost regardless of signal count.
  static List<Map<String, dynamic>> trimSpikeContext(
    List<Map<String, dynamic>> spikes,
  ) {
    return spikes.map((s) {
      final hypotheses = s['hypotheses'] as List? ?? [];
      final topLabel = hypotheses.isNotEmpty
          ? (hypotheses.first as Map<String, dynamic>)['label']?.toString() ??
                ''
          : '';
      return {
        'spike_id': s['spike_id'] ?? '',
        'start': s['start'] ?? '',
        'end': s['end'] ?? '',
        'top_hypothesis': topLabel,
      };
    }).toList();
  }

  // =========================================================================
  // Private static helpers
  // =========================================================================

  static Map<String, dynamic>? _extractJson(String raw) {
    var cleaned = raw
        .trim()
        .replaceAll(RegExp(r'^```[a-zA-Z]*\s*'), '')
        .replaceAll(RegExp(r'\s*```$'), '')
        .trim();
    final s = cleaned.indexOf('{');
    final e = cleaned.lastIndexOf('}');
    if (s == -1 || e == -1 || e <= s) return null;
    return jsonDecode(cleaned.substring(s, e + 1)) as Map<String, dynamic>?;
  }

  static PandaIntent _parseIntent(String s) {
    switch (s.toLowerCase().trim()) {
      case 'answer_label':
        return PandaIntent.answerLabel;
      case 'want_deeper_answer':
        return PandaIntent.wantDeeperAnswer;
      case 'digress':
        return PandaIntent.digress;
      case 'digression_complete':
        return PandaIntent.digressionComplete;
      case 'new_stressor':
        return PandaIntent.newStressor;
      case 'recommend':
        return PandaIntent.recommend;
      case 'skip':
        return PandaIntent.skip;
      case 'calendar_action':
        return PandaIntent.calendarAction;
      case 'priority_action':
        return PandaIntent.priorityAction;
      default:
        return PandaIntent.chitchat;
    }
  }

  static String _buildWarmOpener({
    required String userName,
    required bool hasSpikes,
    required String overallNotes,
    double sleepHours = 0.0,
  }) {
    final spikeSnippet = hasSpikes
        ? 'I noticed some elevated heart rate patterns in your recent data — '
              'I\'ve put together a few questions to help us understand what was going on. '
        : 'Your heart rate looks fairly steady in the data I have. ';

    final sleepSnippet = sleepHours >= 6
        ? 'You got ${sleepHours.toStringAsFixed(1)}h of sleep last night. '
        : sleepHours > 0
        ? 'You only got ${sleepHours.toStringAsFixed(1)}h of sleep — that can amplify stress. '
        : '';

    const invite =
        'What would you like to explore — your patterns, how to plan today, '
        'or something else on your mind?';

    return 'Hey $userName! $spikeSnippet$sleepSnippet$invite';
  }

  static PandaSessionData _fallbackSession(
    String userName,
    String timePhrase,
    List<Map<String, dynamic>> spikes, {
    String notes = '',
    String? scheduleContext,
    String? insightsContext,
    Map<String, Map<String, dynamic>> dashboardMetrics = const {},
  }) {
    return PandaSessionData(
      openerMessage:
          'Hey $userName! I’ve pulled up your health data for today. '
          'What would you like to explore — your stress patterns, how to plan your day, '
          'or something else on your mind?',
      questions: [
        PandaQuestion(
          questionId: 'q_fallback',
          prompt: 'What was happening on $timePhrase?',
          options: const [
            'Work or study',
            'Exercise',
            'Social situation',
            'Commute',
            'Something else',
          ],
          depthPrompts: const [
            'Can you tell me more about what was stressful about that?',
            'How were you feeling physically during that time?',
          ],
        ),
      ],
      overallNotes: notes,
      rawSpikes: spikes,
      scheduleContext: scheduleContext,
      insightsContext: insightsContext,
      dashboardMetrics: dashboardMetrics,
    );
  }

  static double _severity(
    Map<String, dynamic> s,
    double baselineHr,
    double baselineHrv,
  ) {
    final hr = (s['signals']?['heart_rate']?['peak'] ?? 0).toDouble();
    final hrvMin = (s['signals']?['hrv']?['min'] ?? baselineHrv).toDouble();
    // Steps are not a stress signal: ranking by them pushed workout days to
    // the top, so they no longer count toward severity.
    return (hr - baselineHr).clamp(0, 100) +
        (baselineHrv - hrvMin).clamp(0, 100);
  }

  // ponytail: fixed daily thresholds against a 7-day mean; switch to
  // per-user standard deviations if these over- or under-fire.
  static const _restingHrRiseBpm = 7;
  static const _hrvDropMs = 18;
  static const _highStress = 65;

  static List<Map<String, dynamic>> _detectSpikes(
    List<Map> samples,
    double baselineHr,
    double baselineHrv,
  ) {
    bool isSpike(Map s) {
      final hr = (s['hr'] ?? baselineHr).toDouble();
      final hrv = (s['hrv'] ?? baselineHrv).toDouble();
      final stress = (s['stress'] ?? 0).toDouble();
      return hr >= baselineHr + _restingHrRiseBpm ||
          hrv <= baselineHrv - _hrvDropMs ||
          stress >= _highStress;
    }

    final List<Map<String, dynamic>> spikes = [];
    Map<String, dynamic>? cur;
    double peakHr = 0, minHrv = 1e9, peakSteps = 0;

    for (final s in samples) {
      final t = s['t'] as String;
      final hr = (s['hr'] ?? baselineHr).toDouble();
      final hrv = (s['hrv'] ?? baselineHrv).toDouble();
      final steps = (s['steps'] ?? 0).toDouble();

      if (isSpike(s)) {
        cur ??= {
          'spike_id': 'spk_${spikes.length + 1}',
          'start': t,
          'end': t,
          'signals': {
            'heart_rate': {'baseline': baselineHr, 'peak': baselineHr},
            'hrv': {'baseline': baselineHrv, 'min': baselineHrv},
            'steps': {'peak_window': 0.0},
          },
        };
        cur['end'] = t;
        if (hr > peakHr) peakHr = hr;
        if (hrv < minHrv) minHrv = hrv;
        if (steps > peakSteps) peakSteps = steps;
        cur['signals']['heart_rate']['peak'] = peakHr;
        cur['signals']['hrv']['min'] = (minHrv == 1e9) ? baselineHrv : minHrv;
        cur['signals']['steps']['peak_window'] = peakSteps;
      } else {
        if (cur != null) {
          spikes.add(cur);
          cur = null;
          peakHr = 0;
          minHrv = 1e9;
          peakSteps = 0;
        }
      }
    }
    if (cur != null) spikes.add(cur);
    return spikes;
  }

  static List<Map<String, dynamic>> _eventsNear({
    required List<Map> events,
    required String startIso,
    required String endIso,
    required int minutes,
  }) {
    final start = DateTime.parse(startIso);
    final end = DateTime.parse(endIso);
    final lo = start.subtract(Duration(minutes: minutes));
    final hi = end.add(Duration(minutes: minutes));
    final nearby = <Map<String, dynamic>>[];
    for (final e in events) {
      final t = DateTime.parse(e['time'] as String);
      if (!t.isBefore(lo) && !t.isAfter(hi)) {
        nearby.add({
          'time': e['time'],
          'type': e['type'] ?? 'unknown',
          'detail': e['detail'] ?? '',
        });
      }
    }
    return nearby;
  }
}
