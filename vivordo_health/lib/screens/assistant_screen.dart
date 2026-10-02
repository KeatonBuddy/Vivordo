import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';

import '../src/services/ai_consent.dart';
import '../src/services/assistant_actions.dart';
import '../src/services/claude_service.dart';
import '../src/services/daily_priority_service.dart';
import '../src/services/insight_service.dart';
import '../src/services/workout_ai_advice.dart';
import '../src/utils/day_effort.dart';
import '../src/utils/panda_priority_context.dart';
import '../src/utils/workout_opening.dart';
import '../widgets/assistant_blocks.dart';
import '../widgets/contextual_insight_bar.dart';
import '../widgets/crisis_support_card.dart';
import '../widgets/privacy_support_links.dart';
import '../widgets/vivordo_robot.dart';

const _brand = VivordoTheme.brand;

/// Something shown in the thread that isn't a saved message: the card the
/// chat was opened with, a check-in card, or a message that failed to send.
class _LocalItem {
  _LocalItem(this.kind, {this.text, int? t})
    : t = t ?? DateTime.now().millisecondsSinceEpoch;
  final String kind; // opening | checkin | unsent
  final int t;
  String? text;
}

/// One row of the thread, server message or local item, in time order.
typedef _Row = ({
  int t,
  DocumentSnapshot<Map<String, dynamic>>? doc,
  _LocalItem? local,
});

/// Vivordo AI: one continuous conversation, saved on the server
/// (users/{uid}/messages, written by the `assistant` function). Replies are
/// drawn from their blocks: text, charts, proposed changes and data sources.
class AssistantScreen extends StatefulWidget {
  const AssistantScreen({
    super.key,
    this.onClose,
    this.contextPrompt,
    this.onOpenScreen,
  });

  final VoidCallback? onClose;
  final ValueNotifier<ScreenInsight?>? contextPrompt;

  /// Opens one of the app's screens (a source chip's `screen`).
  final void Function(String screen)? onOpenScreen;

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final _svc = ClaudeService();
  final _input = TextEditingController();
  String _uid = '';
  String _name = 'there';

  bool _needsConsent = false;
  bool _ready = false;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  List<DocumentSnapshot<Map<String, dynamic>>> _messages = const [];
  final _local = <_LocalItem>[];

  bool _sending = false;
  String? _pendingText;
  Set<String> _idsBeforeSend = const {};

  // Context only the app has, sent with each message.
  PandaSessionData? _session;
  String? _schedule;
  String? _priorities;
  DateTime? _prioritiesAt;
  ScreenInsight? _screen;
  WorkoutOpening? _workoutOpening;

  // The check-in card about a recent high-stress day.
  List<PandaQuestion> _questions = const [];
  int _question = 0;
  final _answers = <String, String>{};
  bool _spikeMarked = false;

  final _runningActions = <String>{};

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _uid = user?.uid ?? '';
    _name =
        user?.displayName?.split(' ').first ??
        user?.email?.split('@').first ??
        'there';
    widget.contextPrompt?.addListener(_receiveContext);
    _receiveContext();
    unawaited(_start());
  }

  @override
  void dispose() {
    widget.contextPrompt?.removeListener(_receiveContext);
    _workoutOpening?.invalidate();
    _sub?.cancel();
    _input.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_uid.isEmpty) return;
    if (!await AiConsent.granted(_uid)) {
      if (mounted) setState(() => _needsConsent = true);
      return;
    }
    _sub = FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .collection('messages')
        .orderBy('t', descending: true)
        .limit(80)
        .snapshots()
        .listen((snapshot) {
          if (!mounted) return;
          setState(() {
            _messages = snapshot.docs.reversed.toList();
            _ready = true;
            final pending = _pendingText;
            if (pending != null &&
                _messages.any(
                  (m) =>
                      !_idsBeforeSend.contains(m.id) &&
                      m.data()?['role'] == 'user' &&
                      m.data()?['text'] == pending,
                )) {
              _pendingText = null;
            }
          });
        }, onError: (Object _) => setState(() => _ready = true));
    unawaited(_loadContext());
    final source = _screen;
    if (source != null && _workoutOpening != null) {
      unawaited(_loadWorkoutOpening(source));
    }
  }

  Future<void> _allow() async {
    await AiConsent.grant(_uid);
    if (!mounted || FirebaseAuth.instance.currentUser?.uid != _uid) return;
    setState(() => _needsConsent = false);
    await _start();
  }

  /// Opening the chat from a screen's insight bar: show what that screen
  /// said, and for a workout ask for an analysis.
  void _receiveContext() {
    final insight = widget.contextPrompt?.value;
    if (insight == null) return;
    widget.contextPrompt?.value = null;
    _workoutOpening?.invalidate();
    _workoutOpening = insight.screen == 'workout_summary'
        ? WorkoutOpening()
        : null;
    setState(() {
      _screen = insight;
      _local.removeWhere((item) => item.kind == 'opening');
      _local.add(_LocalItem('opening'));
    });
    if (_workoutOpening != null && !_needsConsent && _uid.isNotEmpty) {
      unawaited(_loadWorkoutOpening(insight));
    }
  }

  Future<void> _loadWorkoutOpening(ScreenInsight source) async {
    final opening = _workoutOpening;
    final context = source.context;
    if (opening == null || context == null || !opening.active) return;
    String advice;
    try {
      advice = await loadWorkoutAiAdvice(_uid, context);
    } catch (_) {
      advice =
          'I couldn’t analyze this workout right now. Ask me about it '
          'and I’ll take another look.';
    }
    if (mounted && opening.complete(advice)) setState(() {});
  }

  Future<void> _loadContext() async {
    unawaited(
      PandaPrompts.fetchScheduleContext().then((schedule) {
        if (mounted) setState(() => _schedule = schedule);
      }),
    );
    try {
      final boot = await _svc.startSession(
        analyzeSpikes: _screen == null,
        userName: _name,
        userId: _uid,
      );
      if (!mounted) return;
      setState(() => _session = boot.session);
      final full = await boot.spikeAnalysis;
      if (!mounted || full == null || full.questions.isEmpty) return;
      setState(() {
        _session = full;
        _questions = full.questions;
        _local.add(_LocalItem('checkin'));
      });
    } catch (e) {
      debugPrint('[Assistant] context load failed: $e');
    }
  }

  Future<String> _prioritiesContext() async {
    final now = DateTime.now();
    final at = _prioritiesAt;
    if (_priorities != null &&
        at != null &&
        now.difference(at) < const Duration(minutes: 2)) {
      return _priorities!;
    }
    try {
      final list = await DailyPriorityService.incompleteForDay(
        now,
      ).timeout(const Duration(seconds: 8));
      _prioritiesAt = now;
      return _priorities = buildPandaPriorityContext(list, now);
    } catch (_) {
      return 'Vivordo priorities could not be loaded. Do not assume there are '
          'none or invent tasks. Ask the user for details if needed.';
    }
  }

  String _demandContext() {
    final latest = latestDemand;
    if (latest == null || !DateUtils.isSameDay(latest.at, DateTime.now())) {
      return '';
    }
    final capacity = latest.capacity;
    return '${latest.demand.round()} points '
        '${latest.tomorrow ? 'expected for tomorrow' : 'still ahead today'}'
        '${capacity == null ? '' : ' against Capacity ${capacity.round()}'}, '
        'as of ${DateFormat('h:mm a').format(latest.at)}. '
        'My Day says: "${latest.headline}".';
  }

  String _screenContext() {
    final screen = _screen;
    if (screen == null) return '';
    final guidance = switch (screen.screen) {
      'workout_summary' =>
        'Discuss the selected workout in WORKOUT, not an assumed latest '
            'workout. Base advice on recorded sets and comparisons. Ask about '
            'goals and difficulty where needed. Do not infer form, fatigue, '
            'recovery or medical causes. Suggestions do not change saved '
            'workouts.',
      'fitness' =>
        'Comparisons are against recorded full-day averages, not same-time '
            'activity. Verify current goals and activity before quoting exact '
            'values. Do not infer workout history, recovery needs, or medical '
            'causes from this summary.',
      _ =>
        'Verify current data before quoting exact values. Do not infer '
            'medical causes.',
    };
    final opening = _workoutOpening;
    final message = opening != null && !opening.busy
        ? opening.text
        : screen.message;
    return 'Opened from ${screen.screen} (${screen.title}). Shown at opening '
        '(not live data): $message\n$guidance';
  }

  Future<Map<String, String>> _turnContext() async {
    final spikes = _session?.rawSpikes ?? const [];
    final checkinOpen = _questions.isNotEmpty && _question < _questions.length;
    return {
      'screen': _screenContext(),
      'checkin': checkinOpen
          ? 'A check-in card about a recent high-stress day is showing; the '
                'user answers it in the card, not in chat.'
          : '',
      'insights': _session?.insightsContext ?? '',
      'schedule': _schedule ?? '',
      'priorities': await _prioritiesContext(),
      'spikes': spikes.isEmpty
          ? ''
          : jsonEncode(PandaPrompts.trimSpikeContext(spikes)),
      if (_screen?.screen == 'workout_summary')
        'workout': _screen!.context ?? '',
      'demand': _demandContext(),
    };
  }

  String _errorText(Object error) =>
      error is FirebaseFunctionsException && error.code == 'resource-exhausted'
      ? 'You’ve reached today’s Vivordo AI limit. It resets tomorrow.'
      : 'That didn’t send. Check your connection and try again.';

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _sending || _uid.isEmpty) return;
    if (!await AiConsent.granted(_uid)) {
      if (mounted) setState(() => _needsConsent = true);
      return;
    }
    if (!mounted) return;
    _input.clear();
    setState(() {
      _sending = true;
      _pendingText = text;
      _idsBeforeSend = {for (final m in _messages) m.id};
      _local.removeWhere((item) => item.kind == 'unsent');
    });
    try {
      await _svc
          .processTurn(
            userMessage: text,
            context: await _turnContext(),
            workoutCoach: _screen?.screen == 'workout_summary',
          )
          .timeout(const Duration(seconds: 120));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _pendingText = null;
        _local.add(_LocalItem('unsent', text: '$text\n\n${_errorText(error)}'));
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ── Proposed changes ──────────────────────────────────────────────────────

  Future<void> _setActionStatus(
    DocumentSnapshot<Map<String, dynamic>> doc,
    int index,
    String status, [
    String? note,
  ]) async {
    try {
      await doc.reference.update({
        'actionStatus.$index': status,
        'actionNotes.$index': ?note,
      });
    } catch (e) {
      debugPrint('[Assistant] saving action status failed: $e');
    }
  }

  Future<void> _confirm(
    DocumentSnapshot<Map<String, dynamic>> doc,
    int index,
    Map<String, dynamic> action,
  ) async {
    final key = '${doc.id}:$index';
    setState(() => _runningActions.add(key));
    try {
      if (action['type'] == 'calendar') {
        final calendar = PandaPrompts.calendarActionFrom(action);
        if (calendar == null) throw StateError('That change is incomplete.');
        await applyCalendarAction(calendar);
        await _setActionStatus(doc, index, 'done');
        unawaited(
          PandaPrompts.fetchScheduleContext().then((s) => _schedule = s),
        );
      } else {
        final result = await applyPriorityAction(
          context,
          Map<String, dynamic>.from(action)..remove('type'),
        );
        _priorities = null;
        final status = result.startsWith('Priority')
            ? 'done'
            : result.startsWith('Cancelled')
            ? 'cancelled'
            : 'failed';
        await _setActionStatus(doc, index, status, result);
      }
    } catch (error) {
      await _setActionStatus(
        doc,
        index,
        'failed',
        error.toString().replaceFirst(RegExp(r'^\w+Error: '), ''),
      );
    } finally {
      if (mounted) setState(() => _runningActions.remove(key));
    }
  }

  // ── Check-in card ─────────────────────────────────────────────────────────

  Future<void> _answer(String? answer) async {
    final question = _questions[_question];
    if (!_spikeMarked) {
      _spikeMarked = true;
      unawaited(
        PandaPrompts.markSpikeDaysAnalyzed(
          _uid,
          PandaPrompts.spikeDays(_session?.rawSpikes ?? const []),
        ),
      );
    }
    setState(() {
      _answers[question.prompt] = answer ?? 'skipped';
      _question++;
    });
    if (_question < _questions.length) return;
    final answered = {
      for (final e in _answers.entries)
        if (e.value != 'skipped') e.key: e.value,
    };
    if (answered.isEmpty) return;
    try {
      await InsightService().saveSessionInsight(
        userId: _uid,
        sessionDate: DateTime.now(),
        sessionSlots: const {},
        labeledAnswers: answered,
      );
    } catch (e) {
      debugPrint('[Assistant] saving check-in failed: $e');
    }
  }

  // ── Building the thread ───────────────────────────────────────────────────

  List<_Row> _rows() {
    final rows = <_Row>[
      for (final m in _messages)
        (t: (m.data()?['t'] as num?)?.toInt() ?? 0, doc: m, local: null),
      for (final item in _local) (t: item.t, doc: null, local: item),
    ]..sort((a, b) => a.t.compareTo(b.t));
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return Scaffold(
      backgroundColor: colors.page,
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            Expanded(child: _needsConsent ? _consentView() : _thread()),
            if (!_needsConsent) _inputBar(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    final colors = context.vivordoColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
      child: Row(
        children: [
          if (widget.onClose != null)
            IconButton(
              tooltip: 'Close',
              icon: const Icon(Icons.close_rounded),
              onPressed: widget.onClose,
            ),
          const VivordoRobot(size: 40),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Vivordo AI',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  _sending ? 'Thinking…' : 'Personal health companion',
                  style: TextStyle(color: colors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Data & privacy',
            icon: Icon(Icons.shield_outlined, color: colors.textSecondary),
            onPressed: _showPrivacy,
          ),
        ],
      ),
    );
  }

  Widget _thread() {
    final rows = _rows();
    String? latestAssistantId;
    for (final m in _messages) {
      if (m.data()?['role'] == 'assistant') latestAssistantId = m.id;
    }
    final children = <Widget>[];
    // The support card goes under the reply (which points to it), or under
    // the user's message while no reply has arrived.
    var crisisCard = false;
    for (final row in rows) {
      final local = row.local;
      if (local != null) {
        children.add(_localWidget(local));
        continue;
      }
      final doc = row.doc!;
      final data = doc.data() ?? const {};
      if (data['role'] == 'user') {
        if (crisisCard) children.add(const CrisisSupportCard());
        final text = data['text'] as String? ?? '';
        children.add(AssistantBubble(text: text, mine: true));
        crisisCard = mentionsCrisis(text);
        continue;
      }
      children.addAll(
        _assistantWidgets(doc, latest: doc.id == latestAssistantId),
      );
      if (crisisCard || data['crisis'] == true) {
        children.add(const CrisisSupportCard());
      }
      crisisCard = false;
    }
    final pending = _pendingText;
    if (pending != null) {
      if (crisisCard) children.add(const CrisisSupportCard());
      children.add(AssistantBubble(text: pending, mine: true));
      crisisCard = mentionsCrisis(pending);
    }
    if (crisisCard) children.add(const CrisisSupportCard());
    if (_sending) children.add(const _Typing());
    if (children.isEmpty) children.add(_welcome());

    return ListView.separated(
      reverse: true,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: children.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, i) => children[children.length - 1 - i],
    );
  }

  List<Widget> _assistantWidgets(
    DocumentSnapshot<Map<String, dynamic>> doc, {
    required bool latest,
  }) {
    final data = doc.data() ?? const {};
    final blocks = [
      for (final b in (data['blocks'] as List? ?? const []))
        if (b is Map) Map<String, dynamic>.from(b),
    ];
    if (blocks.isEmpty) {
      blocks.add({'type': 'text', 'text': data['text'] ?? ''});
    }
    final statuses = Map<String, dynamic>.from(
      data['actionStatus'] as Map? ?? {},
    );
    final notes = Map<String, dynamic>.from(data['actionNotes'] as Map? ?? {});
    final widgets = <Widget>[];
    final sources = <Map<String, dynamic>>[];
    var actionIndex = 0;
    for (final block in blocks) {
      switch (block['type']) {
        case 'text':
          widgets.add(
            AssistantBubble(text: block['text'] as String? ?? '', mine: false),
          );
        case 'metric':
          widgets.add(
            MetricChartCard(
              block: block,
              onOpen: block['screen'] is String
                  ? () => widget.onOpenScreen?.call(block['screen'] as String)
                  : null,
            ),
          );
        case 'action' when block['action'] is Map:
          final i = actionIndex++;
          final action = Map<String, dynamic>.from(block['action'] as Map);
          final key = '${doc.id}:$i';
          final status = _runningActions.contains(key)
              ? ActionStatus.running
              : switch (statuses['$i']) {
                  'done' => ActionStatus.done,
                  'cancelled' => ActionStatus.cancelled,
                  'failed' => ActionStatus.failed,
                  _ => latest ? ActionStatus.open : ActionStatus.expired,
                };
          widgets.add(
            ActionCard(
              action: action,
              status: status,
              note: notes['$i'] as String?,
              onConfirm: () => _confirm(doc, i, action),
              onCancel: () => _setActionStatus(doc, i, 'cancelled'),
            ),
          );
        case 'source':
          sources.add(block);
      }
    }
    if (sources.isNotEmpty) {
      widgets.add(SourceChips(sources: sources, onOpen: widget.onOpenScreen));
    }
    final suggestions = [
      for (final s in (data['suggestions'] as List? ?? const []))
        if (s is String) s,
    ];
    if (latest && !_sending && suggestions.isNotEmpty) {
      widgets.add(SuggestionChips(suggestions: suggestions, onTap: _send));
    }
    return [
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, w) in widgets.indexed) ...[
            if (i > 0) const SizedBox(height: 8),
            w,
          ],
        ],
      ),
    ];
  }

  Widget _localWidget(_LocalItem item) {
    switch (item.kind) {
      case 'unsent':
        return Align(
          alignment: Alignment.centerRight,
          child: Text(
            item.text ?? '',
            textAlign: TextAlign.right,
            style: TextStyle(color: Colors.redAccent.shade100, height: 1.4),
          ),
        );
      case 'checkin':
        return _checkinCard();
      default:
        return _openingCard();
    }
  }

  Widget _card({required String label, required List<Widget> children}) {
    final colors = context.vivordoColors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _brand.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: _brand,
              fontSize: 11,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  Widget _openingCard() {
    final screen = _screen;
    if (screen == null) return const SizedBox.shrink();
    final colors = context.vivordoColors;
    final opening = _workoutOpening;
    final chips = switch (screen.screen) {
      'workout_summary' => [
        'Compare performance',
        'Plan my next session',
        'What could I improve?',
      ],
      'fitness' => [
        'Understand my progress',
        'Plan some movement',
        'Review my goals',
      ],
      'my_day' => ['Help me prioritize', 'Find a break', 'Review my schedule'],
      _ => ['What does this mean?', 'What can I do about it?'],
    };
    return _card(
      label: screen.title.toUpperCase(),
      children: [
        if (opening != null && opening.busy)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: LinearProgressIndicator(minHeight: 3),
          ),
        Text(
          opening?.text ?? screen.message,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 15,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 12),
        SuggestionChips(
          suggestions: chips,
          onTap: _sending || (opening?.busy ?? false) ? null : _send,
        ),
      ],
    );
  }

  Widget _checkinCard() {
    final colors = context.vivordoColors;
    final done = _question >= _questions.length;
    if (done) {
      return _card(
        label: 'CHECK-IN',
        children: [
          Text(
            _answers.values.every((a) => a == 'skipped')
                ? 'Skipped. I won’t ask about that day again.'
                : 'Thanks, saved. This helps me spot what drives your stress.',
            style: TextStyle(color: colors.textPrimary, height: 1.4),
          ),
        ],
      );
    }
    final question = _questions[_question];
    return _card(
      label: 'CHECK-IN · ${_question + 1} OF ${_questions.length}',
      children: [
        Text(
          question.prompt,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        SuggestionChips(suggestions: question.options, onTap: _answer),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => _answer(null),
            child: const Text('Skip'),
          ),
        ),
      ],
    );
  }

  Widget _welcome() {
    final colors = context.vivordoColors;
    if (!_ready) {
      return const Padding(
        padding: EdgeInsets.only(top: 80),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hi $_name',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Ask me about your sleep, stress, energy or plans. I can look at '
            'your data and help you organise your day.',
            style: TextStyle(color: colors.textSecondary, height: 1.45),
          ),
          const SizedBox(height: 16),
          SuggestionChips(
            suggestions: const [
              'How did I sleep this week?',
              'What’s my Capacity today?',
              'Plan my day',
            ],
            onTap: _sending ? null : _send,
          ),
        ],
      ),
    );
  }

  Widget _inputBar() {
    final colors = context.vivordoColors;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: colors.card,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Ask Vivordo AI anything',
                filled: true,
                fillColor: colors.input,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            tooltip: 'Send',
            onPressed: _sending ? null : _send,
            style: IconButton.styleFrom(backgroundColor: _brand),
            icon: const Icon(Icons.arrow_upward_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _consentView() {
    final colors = context.vivordoColors;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const VivordoRobot(size: 72),
            const SizedBox(height: 16),
            Text(
              'Allow Vivordo AI?',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              aiConsentDisclosure,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 15,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: _allow, child: const Text('Allow')),
            TextButton(onPressed: widget.onClose, child: const Text('Not now')),
            TextButton(
              onPressed: () =>
                  openVivordoLink(context, Uri.parse(vivordoPrivacyUrl)),
              child: const Text('Privacy Policy'),
            ),
          ],
        ),
      ),
    );
  }

  void _showPrivacy() => showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Privacy & Safety'),
      content: const SingleChildScrollView(
        child: Text(
          'Vivordo AI uses Anthropic’s Claude through Vivordo’s servers. Your '
          'messages and the health, fitness, calendar, priority and '
          'past-conversation information relevant to them are sent to '
          'Anthropic for processing, and your conversation is saved to your '
          'account so it’s here next time.\n\n'
          'Vivordo AI provides wellness information, not medical advice. '
          'Responses can be inaccurate. Consult a qualified healthcare '
          'professional before making medical decisions.',
          style: TextStyle(height: 1.4),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => openVivordoLink(ctx, Uri.parse(vivordoPrivacyUrl)),
          child: const Text('Privacy Policy'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Got it'),
        ),
      ],
    ),
  );
}

class _Typing extends StatelessWidget {
  const _Typing();

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: colors.card,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text('Thinking…', style: TextStyle(color: colors.textSecondary)),
      ),
    );
  }
}
