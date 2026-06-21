// =============================================================================
// insights.dart
//
// Unified Insights model for the Vivordo app.
//
// All insight sources (AI metric analysis, Panda sessions, questionnaire
// processing, goal tracking) write to the same `insights` subcollection,
// nested under the owning user, and are distinguished by the `source` field.
//
// PANDA EXTENSION:
//   When source == "panda", the optional panda* fields are populated:
//     • pandaSlots         — wellness entities extracted turn-by-turn
//     • pandaLabeledAnswers — structured Q→A pairs from the predefined path
//     • pandaCorrections    — append-only audit trail of user edits
//
// Firestore path:  users/{userId}/insights/{autoId}
// Query by source: where('source', isEqualTo: 'panda')
//
// =============================================================================

import 'package:cloud_firestore/cloud_firestore.dart';

// ---------------------------------------------------------------------------
// PandaSlots — typed wrapper for the 11 LLM-extracted wellness entity fields.
// All fields are nullable; only non-empty values are written to Firestore.
// ---------------------------------------------------------------------------

class PandaSlots {
  const PandaSlots({
    this.stressor,
    this.emotion,
    this.intensity,
    this.physicalSymptom,
    this.activity,
    this.location,
    this.timeContext,
    this.copingStrategy,
    this.sleepQuality,
    this.socialContext,
    this.other,
  });

  final String? stressor;
  final String? emotion;

  /// "low" | "medium" | "high"
  final String? intensity;

  final String? physicalSymptom;
  final String? activity;
  final String? location;
  final String? timeContext;
  final String? copingStrategy;
  final String? sleepQuality;
  final String? socialContext;
  final String? other;

  bool get isEmpty => toMap().isEmpty;

  Map<String, dynamic> toMap() {
    final m = <String, dynamic>{};
    if (stressor?.isNotEmpty == true)        m['stressor']         = stressor;
    if (emotion?.isNotEmpty == true)         m['emotion']          = emotion;
    if (intensity?.isNotEmpty == true)       m['intensity']        = intensity;
    if (physicalSymptom?.isNotEmpty == true) m['physical_symptom'] = physicalSymptom;
    if (activity?.isNotEmpty == true)        m['activity']         = activity;
    if (location?.isNotEmpty == true)        m['location']         = location;
    if (timeContext?.isNotEmpty == true)     m['time_context']     = timeContext;
    if (copingStrategy?.isNotEmpty == true)  m['coping_strategy']  = copingStrategy;
    if (sleepQuality?.isNotEmpty == true)    m['sleep_quality']    = sleepQuality;
    if (socialContext?.isNotEmpty == true)   m['social_context']   = socialContext;
    if (other?.isNotEmpty == true)           m['other']            = other;
    return m;
  }

  factory PandaSlots.fromMap(Map<String, dynamic> m) => PandaSlots(
        stressor:        m['stressor']         as String?,
        emotion:         m['emotion']          as String?,
        intensity:       m['intensity']        as String?,
        physicalSymptom: m['physical_symptom'] as String?,
        activity:        m['activity']         as String?,
        location:        m['location']         as String?,
        timeContext:     m['time_context']     as String?,
        copingStrategy:  m['coping_strategy']  as String?,
        sleepQuality:    m['sleep_quality']    as String?,
        socialContext:   m['social_context']   as String?,
        other:           m['other']            as String?,
      );

  /// Build from the raw Map<String,String> accumulated in PandaScreen.
  factory PandaSlots.fromSessionSlots(Map<String, String> slots) => PandaSlots(
        stressor:        slots['stressor'],
        emotion:         slots['emotion'],
        intensity:       slots['intensity'],
        physicalSymptom: slots['physical_symptom'],
        activity:        slots['activity'],
        location:        slots['location'],
        timeContext:     slots['time_context'],
        copingStrategy:  slots['coping_strategy'],
        sleepQuality:    slots['sleep_quality'],
        socialContext:   slots['social_context'],
        other:           slots['other'],
      );
}

// ---------------------------------------------------------------------------
// PandaCorrection — one entry in the labeled-answer audit trail.
// ---------------------------------------------------------------------------

class PandaCorrection {
  const PandaCorrection({
    required this.questionId,
    required this.oldAnswer,
    required this.newAnswer,
    required this.correctedAt,
  });

  final String questionId;
  final String oldAnswer;
  final String newAnswer;
  final Timestamp correctedAt;

  Map<String, dynamic> toMap() => {
        'question_id':  questionId,
        'old_answer':   oldAnswer,
        'new_answer':   newAnswer,
        'corrected_at': correctedAt,
      };

  factory PandaCorrection.fromMap(Map<String, dynamic> m) => PandaCorrection(
        questionId:  m['question_id']  as String,
        oldAnswer:   m['old_answer']   as String,
        newAnswer:   m['new_answer']   as String,
        correctedAt: m['corrected_at'] as Timestamp,
      );
}

// ---------------------------------------------------------------------------
// Insights — unified document model for the `insights` collection.
// ---------------------------------------------------------------------------

class Insights {
  Insights({
    required this.userId,
    required this.createdAt,
    required this.updatedAt,
    this.id,
    this.source,
    this.title,
    this.body,
    this.severity,
    this.category,
    this.relatedMetrics,
    this.relatedMetricsPeriods,
    this.relatedQuestionnareIds,
    this.goalId,
    this.acknowledged,
    this.acknowledgedAt,
    // ── Panda-specific ──────────────────────────────────────────────────────
    this.sessionDate,
    this.pandaSlots,
    this.pandaLabeledAnswers,
    this.pandaCorrections,
    this.summary,
  });

  // ── Core fields (all sources) ─────────────────────────────────────────────

  /// Firestore document ID — null until written.
  String? id;

  final String userId;

  /// Who generated this insight.
  /// Known values: "panda" | "ai_metrics" | "questionnaire" | "goal_tracker"
  String? source;

  String? title;
  String? body;

  /// "info" | "warning" | "critical"
  String? severity;

  /// e.g. "stress" | "sleep" | "activity" | "nutrition"
  String? category;

  List<String>? relatedMetrics;
  List<String>? relatedMetricsPeriods;
  List<String>? relatedQuestionnareIds;
  String? goalId;

  bool? acknowledged;
  Timestamp? acknowledgedAt;

  final Timestamp createdAt;
  Timestamp updatedAt;

  // ── Panda session fields (source == "panda") ──────────────────────────────

  /// When the Panda session that generated this insight started.
  Timestamp? sessionDate;

  /// Wellness entity slots extracted turn-by-turn during the session.
  PandaSlots? pandaSlots;

  /// Structured Q→A pairs from the predefined labeling path.
  /// Keys are question IDs (e.g. "q_1"), values are user answers.
  Map<String, String>? pandaLabeledAnswers;

  /// Append-only audit trail of corrections made from the History tab.
  List<PandaCorrection>? pandaCorrections;

  /// Compact natural-language recap of the session (chat + extracted context).
  /// Bounded to ~160 chars so it is cheap to feed back into future sessions'
  /// user context (see GeminiService.fetchRealUserPayload + aggregateSummary).
  String? summary;

  // ── Factories ─────────────────────────────────────────────────────────────

  /// Build an Insights document from a completed Panda session.
  /// Derives a human-readable title and body from the extracted slots
  /// so the insight is meaningful in any generic insights UI.
  factory Insights.fromPandaSession({
    required String userId,
    required DateTime sessionDate,
    required Map<String, String> sessionSlots,
    required Map<String, String> labeledAnswers,
    List<Map<String, String>>? conversation,
    String? summary,
  }) {
    final slots = PandaSlots.fromSessionSlots(sessionSlots);
    final now = Timestamp.now();

    // Derive a readable title from the top slot values
    final titleParts = <String>[];
    if (slots.stressor?.isNotEmpty == true) titleParts.add(slots.stressor!);
    if (slots.emotion?.isNotEmpty == true)  titleParts.add(slots.emotion!);
    final title = titleParts.isNotEmpty
        ? titleParts.map(_capitalise).join(' · ')
        : 'Panda Check-In';

    // Derive a brief body summary
    final bodyParts = <String>[];
    if (slots.stressor?.isNotEmpty == true)
      bodyParts.add('Stressor: ${slots.stressor}');
    if (slots.emotion?.isNotEmpty == true)
      bodyParts.add('Feeling: ${slots.emotion}');
    if (slots.intensity?.isNotEmpty == true)
      bodyParts.add('Intensity: ${slots.intensity}');
    if (slots.copingStrategy?.isNotEmpty == true)
      bodyParts.add('Coping: ${slots.copingStrategy}');
    final body = bodyParts.isNotEmpty
        ? bodyParts.join(' · ')
        : 'Wellness check-in completed.';

    // Map intensity to severity
    final severity = switch (slots.intensity?.toLowerCase()) {
      'high'   => 'warning',
      'medium' => 'info',
      _        => 'info',
    };

    return Insights(
      userId:               userId,
      source:               'panda',
      title:                title,
      body:                 body,
      severity:             severity,
      category:             'stress',
      sessionDate:          Timestamp.fromDate(sessionDate),
      pandaSlots:           slots,
      pandaLabeledAnswers:  Map<String, String>.from(labeledAnswers),
      pandaCorrections:     [],
      // Prefer the LLM-generated continuity note; fall back to the
      // deterministic recap when it is unavailable (offline / call failed).
      summary:              (summary != null && summary.trim().isNotEmpty)
          ? summary.trim()
          : _buildSessionSummary(slots, labeledAnswers, conversation),
      acknowledged:         false,
      createdAt:            now,
      updatedAt:            now,
    );
  }

  // ── Serialisation ─────────────────────────────────────────────────────────

  Map<String, dynamic> toMap() {
    return {
      'userId':                   userId,
      'source':                   source,
      'title':                    title,
      'body':                     body,
      'severity':                 severity,
      'category':                 category,
      'relatedMetrics':           relatedMetrics,
      'relatedMetricsPeriods':    relatedMetricsPeriods,
      'relatedQuestionnareIds':   relatedQuestionnareIds,
      'goalId':                   goalId,
      'acknowledged':             acknowledged,
      'acknowledgedAt':           acknowledgedAt,
      'createdAt':                createdAt,
      'updatedAt':                updatedAt,
      // Panda fields — only written when source == "panda"
      if (sessionDate != null)
        'sessionDate':            sessionDate,
      if (pandaSlots != null && !pandaSlots!.isEmpty)
        'pandaSlots':             pandaSlots!.toMap(),
      if (pandaLabeledAnswers != null && pandaLabeledAnswers!.isNotEmpty)
        'pandaLabeledAnswers':    pandaLabeledAnswers,
      if (pandaCorrections != null && pandaCorrections!.isNotEmpty)
        'pandaCorrections':       pandaCorrections!.map((c) => c.toMap()).toList(),
      if (summary != null && summary!.isNotEmpty)
        'summary':                summary,
    };
  }

  factory Insights.fromMap(Map<String, dynamic> map) {
    // Parse optional panda corrections list
    List<PandaCorrection>? corrections;
    if (map['pandaCorrections'] is List) {
      corrections = (map['pandaCorrections'] as List)
          .map((c) => PandaCorrection.fromMap(Map<String, dynamic>.from(c as Map)))
          .toList();
    }

    // Parse optional panda slots
    PandaSlots? slots;
    if (map['pandaSlots'] is Map) {
      slots = PandaSlots.fromMap(Map<String, dynamic>.from(map['pandaSlots'] as Map));
    }

    // Parse optional labeled answers
    Map<String, String>? labeledAnswers;
    if (map['pandaLabeledAnswers'] is Map) {
      labeledAnswers = Map<String, String>.from(
          map['pandaLabeledAnswers'] as Map);
    }

    return Insights(
      userId:                   map['userId']    as String? ?? '',
      source:                   map['source']    as String?,
      title:                    map['title']     as String?,
      body:                     map['body']      as String?,
      severity:                 map['severity']  as String?,
      category:                 map['category']  as String?,
      relatedMetrics:           map['relatedMetrics'] != null
          ? List<String>.from(map['relatedMetrics'] as List)
          : null,
      relatedMetricsPeriods:    map['relatedMetricsPeriods'] != null
          ? List<String>.from(map['relatedMetricsPeriods'] as List)
          : null,
      relatedQuestionnareIds:   map['relatedQuestionnareIds'] != null
          ? List<String>.from(map['relatedQuestionnareIds'] as List)
          : null,
      goalId:                   map['goalId']        as String?,
      acknowledged:             map['acknowledged']  as bool?,
      acknowledgedAt:           map['acknowledgedAt'] as Timestamp?,
      // createdAt/updatedAt can be transiently null in a LOCAL snapshot while a
      // FieldValue.serverTimestamp() write is pending (hasPendingWrites). Fall
      // back so deserialisation never throws on the optimistic local update.
      createdAt:                (map['createdAt'] as Timestamp?) ??
                                (map['updatedAt'] as Timestamp?) ??
                                Timestamp.now(),
      updatedAt:                (map['updatedAt'] as Timestamp?) ??
                                (map['createdAt'] as Timestamp?) ??
                                Timestamp.now(),
      sessionDate:              map['sessionDate']   as Timestamp?,
      pandaSlots:               slots,
      pandaLabeledAnswers:      labeledAnswers,
      pandaCorrections:         corrections,
      summary:                  map['summary']       as String?,
    );
  }

  /// Build from a Firestore DocumentSnapshot.
  factory Insights.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final insight = Insights.fromMap(doc.data()!);
    insight.id = doc.id;
    return insight;
  }

  // ── Firestore write (original API preserved) ───────────────────────────────

  Future<DocumentReference<Map<String, dynamic>>> toFirestore(
      String userId) async {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('insights')
        .add(toMap());
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  static String _capitalise(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  /// Builds a compact, deterministic recap combining the extracted context
  /// (stressor/emotion/intensity/coping) with a digest of the user's own
  /// words from the chat. Bounded to ~160 chars so it stays cheap to feed back
  /// into future sessions. Returns null when there is nothing worth recording.
  static String? _buildSessionSummary(
    PandaSlots slots,
    Map<String, String> labeledAnswers,
    List<Map<String, String>>? conversation,
  ) {
    final ctx = <String>[];
    if (slots.stressor?.isNotEmpty == true)       ctx.add(slots.stressor!);
    if (slots.emotion?.isNotEmpty == true)        ctx.add('felt ${slots.emotion}');
    if (slots.intensity?.isNotEmpty == true)      ctx.add('${slots.intensity} intensity');
    if (slots.copingStrategy?.isNotEmpty == true) ctx.add('tried ${slots.copingStrategy}');

    // The user's own words — the "chat" part. Keep the last two user turns.
    final userWords = (conversation ?? const <Map<String, String>>[])
        .where((t) => t['role'] == 'user')
        .map((t) => t['text']?.trim() ?? '')
        .where((t) => t.isNotEmpty)
        .toList();
    final recentUserWords =
        userWords.length > 2 ? userWords.sublist(userWords.length - 2) : userWords;

    final parts = <String>[];
    if (ctx.isNotEmpty) parts.add(ctx.join(', '));
    if (recentUserWords.isNotEmpty) {
      parts.add('User: "${recentUserWords.join('" / "')}"');
    }
    // Fall back to labeled answers when neither slots nor chat were captured.
    if (parts.isEmpty && labeledAnswers.isNotEmpty) {
      final answers =
          labeledAnswers.values.where((v) => v.isNotEmpty).take(2).join('; ');
      if (answers.isNotEmpty) parts.add(answers);
    }

    if (parts.isEmpty) return null;
    return _truncate(parts.join('. '), 160);
  }

  static String _truncate(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max - 1).trimRight()}…';
}
