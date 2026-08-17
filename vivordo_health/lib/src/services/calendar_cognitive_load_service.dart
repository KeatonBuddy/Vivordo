import 'dart:convert';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Calendar metadata used to estimate how mentally demanding an event is.
///
/// Attendee names and email addresses are intentionally excluded so the AI
/// fallback receives only the minimum information needed for classification.
class CalendarCognitiveEvent {
  const CalendarCognitiveEvent({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    this.description = '',
    this.attendeeCount = 0,
    this.isOrganizer = false,
    this.isOptional = false,
    this.isOnlineMeeting = false,
    this.showsAsFree = false,
    this.hasTightTransition = false,
  });

  final String id;
  final String title;
  final String description;
  final DateTime start;
  final DateTime end;
  final int attendeeCount;
  final bool isOrganizer;
  final bool isOptional;
  final bool isOnlineMeeting;
  final bool showsAsFree;
  final bool hasTightTransition;

  int get durationMinutes => end.difference(start).inMinutes.clamp(0, 1440);
}

enum CognitiveLoadLevel { low, moderate, high }

class CognitiveLoadScore {
  const CognitiveLoadScore({
    required this.eventId,
    required this.score,
    required this.category,
    required this.reason,
    required this.usedAi,
  });

  final String eventId;
  final int score;
  final String category;
  final String reason;
  final bool usedAi;

  CognitiveLoadLevel get level => score >= 60
      ? CognitiveLoadLevel.high
      : score >= 30
      ? CognitiveLoadLevel.moderate
      : CognitiveLoadLevel.low;
}

class CalendarCognitiveLoadService {
  CalendarCognitiveLoadService._();

  static const _storage = FlutterSecureStorage();
  static const _cacheKey = 'calendar_cognitive_load_ai_cache_v1';
  static const _lastAiBatchDateKey = 'calendar_cognitive_load_last_ai_date_v1';
  static const _maxAiEventsPerBatch = 5;
  static const _maxCacheEntries = 200;

  static final _aiModel = FirebaseAI.googleAI().generativeModel(
    model: 'gemini-2.5-flash',
    generationConfig: GenerationConfig(
      responseMimeType: 'application/json',
      responseSchema: Schema(
        SchemaType.object,
        properties: {
          'events': Schema(
            SchemaType.array,
            items: Schema(
              SchemaType.object,
              properties: {
                'id': Schema(SchemaType.string),
                'score': Schema(SchemaType.integer),
                'category': Schema(SchemaType.string),
                'reason': Schema(SchemaType.string),
              },
            ),
          ),
        },
      ),
      candidateCount: 1,
      temperature: 0,
      maxOutputTokens: 400,
    ),
  );

  /// Scores events locally first. Only unclear, uncached events are sent in a
  /// single small AI batch, capped at five events per refresh.
  static Future<List<CognitiveLoadScore>> scoreEvents(
    List<CalendarCognitiveEvent> events,
  ) async {
    if (events.isEmpty) return const [];

    final local = events.map(scoreLocally).toList();
    final cache = await _readCache();
    final resolved = <String, CognitiveLoadScore>{};
    final uncertain = <CalendarCognitiveEvent>[];

    for (var i = 0; i < events.length; i++) {
      final event = events[i];
      final localScore = local[i];
      if (!_needsAi(event, localScore)) {
        resolved[event.id] = localScore;
        continue;
      }

      final cached = cache[_signature(event)];
      if (cached is Map<String, dynamic>) {
        resolved[event.id] = _scoreFromJson(event.id, cached, usedAi: true);
      } else if (uncertain.length < _maxAiEventsPerBatch) {
        uncertain.add(event);
      } else {
        resolved[event.id] = localScore;
      }
    }

    if (uncertain.isNotEmpty && await _canUseAiToday()) {
      try {
        final aiScores = await _scoreUncertainEvents(uncertain);
        for (final event in uncertain) {
          final score = aiScores[event.id];
          if (score == null) {
            resolved[event.id] = scoreLocally(event);
            continue;
          }
          resolved[event.id] = score;
          cache[_signature(event)] = {
            'score': score.score,
            'category': score.category,
            'reason': score.reason,
            'cachedAt': DateTime.now().toUtc().toIso8601String(),
          };
        }
        await _writeCache(cache);
        await _markAiUsedToday();
      } catch (error) {
        debugPrint('Calendar cognitive-load AI fallback failed: $error');
        for (final event in uncertain) {
          resolved[event.id] = scoreLocally(event);
        }
      }
    } else {
      for (final event in uncertain) {
        resolved[event.id] = scoreLocally(event);
      }
    }

    return events.map((event) => resolved[event.id]!).toList();
  }

  @visibleForTesting
  static CognitiveLoadScore scoreLocally(CalendarCognitiveEvent event) {
    final text = '${event.title} ${event.description}'.toLowerCase();
    var score = 25;
    var category = 'unclear';
    var reason = 'Limited event context';

    if (_containsAny(text, _highLoadTerms)) {
      score += 38;
      category = 'high-focus';
      reason = 'The event appears to require preparation or performance';
    } else if (_containsAny(text, _lowLoadTerms)) {
      score -= 22;
      category = 'low-demand';
      reason = 'The event appears routine, passive, or logistical';
    } else if (_containsAny(text, _moderateLoadTerms)) {
      score += 18;
      category = 'collaboration';
      reason = 'The event likely requires active discussion or decisions';
    }

    if (_containsAny(text, _preparationTerms)) score += 12;
    if (event.isOrganizer) score += 8;
    if (event.attendeeCount >= 5) {
      score += 10;
    } else if (event.attendeeCount >= 2) {
      score += 5;
    }
    if (event.isOnlineMeeting) score += 4;
    if (event.hasTightTransition) score += 8;
    if (event.isOptional) score -= 10;
    if (event.showsAsFree) score -= 12;

    // Duration is deliberately capped so a long passive block cannot become
    // high-load merely because it occupies several hours.
    if (event.durationMinutes >= 90) score += 5;
    if (event.durationMinutes <= 20) score -= 3;

    return CognitiveLoadScore(
      eventId: event.id,
      score: score.clamp(0, 100),
      category: category,
      reason: reason,
      usedAi: false,
    );
  }

  static bool _needsAi(
    CalendarCognitiveEvent event,
    CognitiveLoadScore localScore,
  ) {
    if (localScore.category != 'unclear') return false;
    if (event.title.trim().isEmpty) return false;
    return localScore.score >= 20 && localScore.score <= 59;
  }

  static Future<Map<String, CognitiveLoadScore>> _scoreUncertainEvents(
    List<CalendarCognitiveEvent> events,
  ) async {
    final compactEvents = events
        .map(
          (event) => {
            'id': event.id,
            'title': _truncate(event.title, 100),
            if (event.description.trim().isNotEmpty)
              'description': _truncate(event.description, 180),
            'durationMinutes': event.durationMinutes,
            'attendeeCount': event.attendeeCount,
            'isOrganizer': event.isOrganizer,
            'isOptional': event.isOptional,
            'isOnlineMeeting': event.isOnlineMeeting,
            'hasTightTransition': event.hasTightTransition,
          },
        )
        .toList();

    final response = await _aiModel
        .generateContent([
          Content.text('''
Classify the intrinsic cognitive demand of these calendar events from 0-100.
Do not treat blocked time or long duration alone as cognitive load. Routine
errands, drop-offs, travel, meals, passive appointments, and reminders are
usually low. Presentations, interviews, exams, negotiations, incident response,
and decision-heavy meetings are high. Ordinary meetings are moderate.

Return each id once. Keep category to 1-2 words and reason under 12 words.
Events: ${jsonEncode(compactEvents)}
'''),
        ])
        .timeout(const Duration(seconds: 8));

    final decoded = jsonDecode(response.text ?? '{}') as Map<String, dynamic>;
    final items = decoded['events'] as List<dynamic>? ?? const [];
    final output = <String, CognitiveLoadScore>{};
    final allowedIds = events.map((event) => event.id).toSet();
    for (final item in items.whereType<Map<String, dynamic>>()) {
      final id = item['id']?.toString() ?? '';
      if (!allowedIds.contains(id)) continue;
      output[id] = _scoreFromJson(id, item, usedAi: true);
    }
    return output;
  }

  static CognitiveLoadScore _scoreFromJson(
    String eventId,
    Map<String, dynamic> json, {
    required bool usedAi,
  }) {
    final rawScore = json['score'];
    final score = rawScore is num ? rawScore.round() : 40;
    return CognitiveLoadScore(
      eventId: eventId,
      score: score.clamp(0, 100),
      category: _truncate(json['category']?.toString() ?? 'unclear', 30),
      reason: _truncate(json['reason']?.toString() ?? 'AI classification', 100),
      usedAi: usedAi,
    );
  }

  static Future<Map<String, dynamic>> _readCache() async {
    try {
      final encoded = await _storage.read(key: _cacheKey);
      if (encoded == null || encoded.isEmpty) return {};
      return jsonDecode(encoded) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  static Future<void> _writeCache(Map<String, dynamic> cache) async {
    try {
      if (cache.length > _maxCacheEntries) {
        final entries = cache.entries.toList()
          ..sort((a, b) {
            final aTime = (a.value as Map?)?['cachedAt']?.toString() ?? '';
            final bTime = (b.value as Map?)?['cachedAt']?.toString() ?? '';
            return bTime.compareTo(aTime);
          });
        cache
          ..clear()
          ..addEntries(entries.take(_maxCacheEntries));
      }
      await _storage.write(key: _cacheKey, value: jsonEncode(cache));
    } catch (error) {
      debugPrint('Calendar cognitive-load cache write failed: $error');
    }
  }

  static String _signature(CalendarCognitiveEvent event) {
    final normalized = [
      event.title.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim(),
      _truncate(event.description.toLowerCase(), 180),
      (event.durationMinutes / 30).round(),
      event.attendeeCount.clamp(0, 10),
      event.isOrganizer,
      event.isOptional,
      event.isOnlineMeeting,
      event.hasTightTransition,
    ].join('|');
    return _fnv1a(normalized);
  }

  static String _fnv1a(String value) {
    var hash = 0x811C9DC5;
    for (final byte in utf8.encode(value)) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  static Future<bool> _canUseAiToday() async {
    try {
      final lastDate = await _storage.read(key: _lastAiBatchDateKey);
      return lastDate != _localDateKey(DateTime.now());
    } catch (_) {
      return true;
    }
  }

  static Future<void> _markAiUsedToday() => _storage.write(
    key: _lastAiBatchDateKey,
    value: _localDateKey(DateTime.now()),
  );

  static String _localDateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static bool _containsAny(String text, List<String> terms) =>
      terms.any((term) => text.contains(term));

  static String _truncate(String value, int maxLength) =>
      value.length <= maxLength ? value : value.substring(0, maxLength);

  static const _lowLoadTerms = [
    'drop off',
    'drop-off',
    'pickup',
    'pick up',
    'delivery',
    'oil change',
    'vehicle service',
    'car service',
    'commute',
    'travel',
    'flight',
    'lunch',
    'dinner',
    'break',
    'workout',
    'gym',
    'walk',
    'reminder',
    'hold',
    'out of office',
  ];

  static const _moderateLoadTerms = [
    'sync',
    '1:1',
    'one on one',
    'call',
    'planning',
    'brainstorm',
    'review',
    'workshop',
    'appointment',
  ];

  static const _highLoadTerms = [
    // Focused professional work.
    'app development',
    'software development',
    'coding',
    'programming',
    'deep work',
    'focus work',
    'focus block',
    'deep focus',
    'project development',
    'product development',
    'feature development',
    'web development',
    'mobile development',
    'debugging',
    'troubleshooting',
    'technical design',
    'system design',
    'architecture review',
    'code review',
    'release planning',
    'production deployment',
    'product launch',
    'data analysis',
    'financial analysis',
    'financial modeling',
    'report writing',
    'technical writing',
    'proposal writing',
    'grant writing',
    'contract review',
    'legal review',
    'audit preparation',
    'budget planning',
    'strategic planning',
    'decision meeting',
    'stakeholder presentation',
    'client presentation',
    'workshop facilitation',
    'crisis management',
    'urgent issue',
    'critical issue',
    'hiring interview',

    // Academically demanding work.
    'study session',
    'exam preparation',
    'test preparation',
    'midterm',
    'final exam',
    'quiz',
    'assignment',
    'homework',
    'coursework',
    'research project',
    'research paper',
    'essay writing',
    'paper writing',
    'lab report',
    'laboratory',
    'practical exam',
    'oral exam',
    'class presentation',
    'group presentation',
    'capstone project',
    'thesis',
    'thesis defense',
    'dissertation',
    'dissertation defense',
    'certification exam',
    'application deadline',
    'project deadline',
    'assignment deadline',

    // Other established high-demand event types.
    'meeting',
    'presentation',
    'presenting',
    'interview',
    'exam',
    'audition',
    'performance review',
    'deadline',
    'negotiation',
    'incident response',
    'client pitch',
    'board meeting',
    'hearing',
    'assessment',
  ];

  static const _preparationTerms = [
    'prepare',
    'preparation',
    'decision',
    'strategy',
    'proposal',
    'demo',
    'facilitate',
    'lead ',
  ];
}
