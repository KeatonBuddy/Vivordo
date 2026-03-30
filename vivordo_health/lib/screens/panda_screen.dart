import 'package:flutter/material.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:async';
import '../src/services/gemini_service.dart';
import '../src/services/recommendation_engine.dart';
import '../src/services/panda_recommendations.dart';

// =============================================================================
// DIALOGUE STATE MACHINE
// =============================================================================
//
// Implements the hybrid ICM+LLM pattern with a dialogue STACK:
//
//   onPath       →  Asking predefined labeling questions (structured path).
//
//   inDepth      →  User chose to go deeper on the current question.
//                   We stay on the same question but follow LLM-generated
//                   probing follow-ups until the user is satisfied.
//
//   inDigression →  User left the predefined path entirely (advice/support).
//                   The interrupted question is stored in _digressionStack.
//                   After the digression resolves, we pop the stack and
//                   seamlessly resume the predefined path.
//
//   free         →  Predefined path is complete. Fully open conversation.
//
// =============================================================================

enum _DialogueState { onPath, inDepth, inDigression, free }

// =============================================================================
// PandaScreen
// =============================================================================

class PandaScreen extends StatefulWidget {
  const PandaScreen({super.key});

  @override
  State<PandaScreen> createState() => _PandaScreenState();
}

class _PandaScreenState extends State<PandaScreen>
    with SingleTickerProviderStateMixin {
  // ── Theme ──────────────────────────────────────────────────────────────────
  static const Color _purple = Color(0xFF7B6EF6);
  static const Color _teal = Color(0xFF0ABFBC);
  static const Color _ink = Color(0xFF2D3142);
  static const Color _bg = Color(0xFFF2F2F7);

  // ── Service ────────────────────────────────────────────────────────────────
  final GeminiService _svc = GeminiService();

  // ── Session ────────────────────────────────────────────────────────────────
  PandaSessionData? _session;
  bool _loading = true;
  String? _error;
  DateTime? _sessionStart;

  // ── Question queue  (mutable — new stressors get injected) ─────────────────
  final List<PandaQuestion> _questionQueue = [];
  int _qIdx = 0;

  // ── Depth tracking ─────────────────────────────────────────────────────────
  // How many depth turns we've spent on the current question.
  int _depthTurns = 0;
  // Maximum depth turns per question before gently steering back.
  static const int _maxDepth = 5;

  // ── Dialogue state ─────────────────────────────────────────────────────────
  _DialogueState _state = _DialogueState.onPath;

  // ── Digression stack  (supports nested digressions if needed) ──────────────
  final List<_DigressionFrame> _digressionStack = [];

  // ── Graph tracking ─────────────────────────────────────────────────────────
  final List<_ConvNode> _graphNodes = [];
  final Set<String> _injectedIds = {};
  String? _interruptedNodeId;

  // ── Slot accumulation  (merged across ALL turns) ───────────────────────────
  final Map<String, String> _sessionSlots = {};

  // ── Recommendation tracking ────────────────────────────────────────────────
  // IDs of recs already shown this session (avoids repeating the same card).
  final Set<String> _shownRecIds = {};

  // ── Chat ───────────────────────────────────────────────────────────────────
  final List<_Turn> _turns = [];
  final Map<String, String> _answers = {};
  bool _sessionComplete = false;
  bool _pandaTyping = false;

  // ── Input ──────────────────────────────────────────────────────────────────
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  // ── History ────────────────────────────────────────────────────────────────
  final List<_HistoryRecord> _history = [];
  static const int _maxHistory = 20;

  // ── Tab controller ─────────────────────────────────────────────────────────
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    // Pre-load recommendation catalog from assets/recommendations.json
    PandaRecommendations.load();
    _loadSession();
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _tabCtrl.dispose();
    super.dispose();
  }

  // ===========================================================================
  // Session init
  // ===========================================================================

  Future<void> _loadSession() async {
    final startedAt = DateTime.now();
    _sessionStart = startedAt;

    setState(() {
      _loading = true;
      _error = null;
      _turns.clear();
      _answers.clear();
      _questionQueue.clear();
      _qIdx = 0;
      _depthTurns = 0;
      _state = _DialogueState.onPath;
      _digressionStack.clear();
      _graphNodes.clear();
      _injectedIds.clear();
      _interruptedNodeId = null;
      _sessionSlots.clear();
      _shownRecIds.clear();
      _sessionComplete = false;
      _session = null;
    });

    try {
      final session = await _svc
          .analyzePandaSession()
          .timeout(const Duration(seconds: 90));

      if (!mounted) return;
      setState(() {
        _session = session;
        _questionQueue.addAll(session.questions);
        _loading = false;
      });

      await _pandaSay(session.openerMessage);

      if (_questionQueue.isNotEmpty) {
        await _pandaSay(_questionQueue.first.prompt);
      } else {
        setState(() {
          _sessionComplete = true;
          _state = _DialogueState.free;
        });
        _saveHistory(startedAt, success: true);
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Took too long. Tap retry to try again.';
      });
      _saveHistory(startedAt, success: false, error: 'Timed out after 90s.');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Something went wrong: $e';
      });
      _saveHistory(startedAt, success: false, error: e.toString());
    }
  }

  // ===========================================================================
  // History
  // ===========================================================================

  void _saveHistory(DateTime startedAt,
      {required bool success, String? error}) {
    if (!mounted) return;
    setState(() {
      _history.insert(
        0,
        _HistoryRecord(
          startedAt: startedAt,
          endedAt: DateTime.now(),
          success: success,
          error: error,
          turns: List<_Turn>.from(_turns),
          answers: Map<String, String>.from(_answers),
          overallNotes: _session?.overallNotes ?? '',
          graphNodes: List<_ConvNode>.from(_graphNodes),
          sessionSlots: Map<String, String>.from(_sessionSlots),
        ),
      );
      if (_history.length > _maxHistory) {
        _history.removeRange(_maxHistory, _history.length);
      }
    });
  }

  // ===========================================================================
  // Panda says (with typing indicator delay)
  // ===========================================================================

  Future<void> _pandaSay(String text,
      {int typingMs = 1100,
      _TurnKind kind = _TurnKind.normal,
      List<PandaRec> recs = const []}) async {
    if (!mounted) return;
    setState(() => _pandaTyping = true);
    _scrollBottom();
    await Future.delayed(Duration(milliseconds: typingMs));
    if (!mounted) return;
    setState(() {
      _pandaTyping = false;
      _turns.add(_Turn.assistant(text, kind: kind, recs: recs));
    });
    _scrollBottom();
  }

  void _scrollBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    });
  }

  PandaQuestion? get _currentQ =>
      _qIdx < _questionQueue.length ? _questionQueue[_qIdx] : null;

  // ===========================================================================
  // Chip tap  —  treated as direct answer to current question
  // ===========================================================================

  Future<void> _chipTap(String option) async {
    if (_pandaTyping || _sessionComplete) return;
    final q = _currentQ;
    if (q == null) return;

    setState(() {
      _turns.add(_Turn.user(option));
      _answers[q.questionId] = option;
      _graphNodes.add(_ConvNode(
        questionId: q.questionId,
        questionText: q.prompt,
        answer: option,
        isBranch: _injectedIds.contains(q.questionId),
        parentNodeId:
            _injectedIds.contains(q.questionId) ? _interruptedNodeId : null,
      ));
      _qIdx++;
      _depthTurns = 0;
      _state = _DialogueState.onPath;
    });
    _scrollBottom();
    await _advanceOrComplete();
  }

  // ===========================================================================
  // Free-text submit  —  routed through the full dialogue state machine
  // ===========================================================================

  Future<void> _submit() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _pandaTyping) return;
    _inputCtrl.clear();

    setState(() => _turns.add(_Turn.user(text)));
    _scrollBottom();

    final session = _session;
    if (session == null) return;

    final history = _turns
        .map((t) => {
              'role': t.role == _Role.user ? 'user' : 'assistant',
              'text': t.text,
            })
        .toList();

    setState(() => _pandaTyping = true);
    _scrollBottom();

    try {
      final reply = await _svc
          .processTurn(
            userMessage: text,
            conversationHistory: history,
            spikeContext: session.rawSpikes,
            isOnPredefinedPath: _state == _DialogueState.onPath ||
                _state == _DialogueState.inDepth,
            isInDigression: _state == _DialogueState.inDigression,
            digressionTurnCount: _digressionStack.isEmpty
                ? 0
                : _digressionStack.last.turnCount,
            pendingQuestionId: _currentQ?.questionId,
            pendingQuestionPrompt: _currentQ?.prompt,
            digressionTopic: _digressionStack.isEmpty
                ? null
                : _digressionStack.last.topic,
            accumulatedSlots: Map<String, String>.from(_sessionSlots),
          )
          .timeout(const Duration(seconds: 35));

      if (!mounted) return;
      setState(() => _pandaTyping = false);

      // ── Merge slots ──────────────────────────────────────────────────────
      if (reply.filledSlots != null) {
        setState(() => _sessionSlots.addAll(reply.filledSlots!));
      }

      // ── Route on intent ──────────────────────────────────────────────────
      switch (reply.intent) {

        // ── User answered the current labeling question ──────────────────
        case PandaIntent.answerLabel:
          final q = _currentQ;
          if (q != null) {
            setState(() {
              _answers[q.questionId] = text;
              _graphNodes.add(_ConvNode(
                questionId: q.questionId,
                questionText: q.prompt,
                answer: text,
                isBranch: _injectedIds.contains(q.questionId),
                parentNodeId: _injectedIds.contains(q.questionId)
                    ? _interruptedNodeId
                    : null,
              ));
              _qIdx++;
              _depthTurns = 0;
              // If we were in a digression, pop it now that a label was captured
              if (_state == _DialogueState.inDigression &&
                  _digressionStack.isNotEmpty) {
                _digressionStack.removeLast();
              }
              _state = _DialogueState.onPath;
            });
          }
          await _pandaSay(reply.message, typingMs: 0);
          await _advanceOrComplete();

        // ── User wants to go deeper on this topic ───────────────────────
        case PandaIntent.wantDeeperAnswer:
          setState(() {
            _depthTurns++;
            _state = _DialogueState.inDepth;
          });
          await _pandaSay(reply.message, typingMs: 0, kind: _TurnKind.depth);

          if (_depthTurns < _maxDepth && reply.depthFollowUp != null) {
            // Ask the LLM-generated depth probe
            await _pandaSay(reply.depthFollowUp!, kind: _TurnKind.depth);
          } else if (_depthTurns >= _maxDepth) {
            // Gently steer back
            await _pandaSay(
              'Thanks for sharing all of that 💜 Let\'s note that and keep going.',
              kind: _TurnKind.normal,
            );
            final q = _currentQ;
            if (q != null) {
              // Use what we know as the label
              setState(() {
                _answers[q.questionId] = text;
                _graphNodes.add(_ConvNode(
                  questionId: q.questionId,
                  questionText: q.prompt,
                  answer: text,
                  isBranch: _injectedIds.contains(q.questionId),
                  parentNodeId: _injectedIds.contains(q.questionId)
                      ? _interruptedNodeId
                      : null,
                ));
                _qIdx++;
                _depthTurns = 0;
                _state = _DialogueState.onPath;
              });
            }
            await _advanceOrComplete();
          }

        // ── User left the path (advice / support / tips) ─────────────────
        case PandaIntent.digress:
          setState(() {
            _state = _DialogueState.inDigression;
            _digressionStack.add(_DigressionFrame(
              pendingQuestionId: _currentQ?.questionId ?? '',
              pendingQuestionPrompt: _currentQ?.prompt ?? '',
              topic: text,
            ));
          });
          await _pandaSay(reply.message, typingMs: 0, kind: _TurnKind.digression);

        // ── User signals digression is done, resume predefined path ──────
        case PandaIntent.digressionComplete:
          final frame = _digressionStack.isNotEmpty
              ? _digressionStack.removeLast()
              : null;
          setState(() {
            _state = frame == null || _qIdx >= _questionQueue.length
                ? _DialogueState.free
                : _DialogueState.onPath;
          });
          await _pandaSay(reply.message, typingMs: 0, kind: _TurnKind.digression);

          // Resume predefined path
          if (_state == _DialogueState.onPath && _currentQ != null) {
            await Future.delayed(const Duration(milliseconds: 500));
            await _pandaSay(
              'Let\'s pick back up 🐼  —  ${_currentQ!.prompt}',
              kind: _TurnKind.normal,
            );
          }

        // ── New stressor mentioned — inject a follow-up question ──────────
        case PandaIntent.newStressor:
          if (reply.injectedQuestion != null) {
            setState(() {
              _interruptedNodeId = _currentQ?.questionId;
              _injectedIds.add(reply.injectedQuestion!.questionId);
              final at = _qIdx.clamp(0, _questionQueue.length);
              _questionQueue.insert(at, reply.injectedQuestion!);
            });
          }
          await _pandaSay(reply.message, typingMs: 0);
          if (_currentQ != null) {
            await _pandaSay(_currentQ!.prompt);
          }

        // ── Skip ────────────────────────────────────────────────────────
        case PandaIntent.skip:
          final q = _currentQ;
          if (q != null) {
            setState(() {
              _answers[q.questionId] = 'skipped';
              _qIdx++;
              _depthTurns = 0;
            });
          }
          await _pandaSay(reply.message, typingMs: 0);
          await _advanceOrComplete();

        // ── Recommendations ──────────────────────────────────────────────
        case PandaIntent.recommend:
          // Run the engine with current session slots + LLM hint
          final recs = RecommendationEngine.recommend(
            sessionSlots: Map<String, String>.from(_sessionSlots),
            llmHint: reply.recHint,
            excludeIds: Set<String>.from(_shownRecIds),
          );
          // Track shown recs to avoid repetition later in the session
          setState(() => _shownRecIds.addAll(recs.map((r) => r.id)));
          await _pandaSay(
            reply.message,
            typingMs: 0,
            kind: _TurnKind.recommend,
            recs: recs,
          );

        // ── Chitchat / unclassified ──────────────────────────────────────
        case PandaIntent.chitchat:
          // Update digression depth counter
          if (_state == _DialogueState.inDigression &&
              _digressionStack.isNotEmpty) {
            setState(() => _digressionStack.last.turnCount++);
          }
          await _pandaSay(reply.message, typingMs: 0);
          // Don't advance — stay exactly where we are
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _pandaTyping = false);
      await _pandaSay(
        'Sorry, I had a little hiccup — could you try again? 🐼',
        typingMs: 0,
      );
    }
  }

  // ===========================================================================
  // Advance or complete
  // ===========================================================================

  Future<void> _advanceOrComplete() async {
    if (_qIdx < _questionQueue.length) {
      await _pandaSay(_questionQueue[_qIdx].prompt);
    } else {
      if (!_sessionComplete) {
        await _pandaSay(
          'Thanks so much for sharing all of that! 💜  '
          'I\'ve captured everything. You can keep chatting or start a new session.',
          typingMs: 900,
        );
        if (!mounted) return;
        setState(() {
          _sessionComplete = true;
          _state = _DialogueState.free;
        });
        _saveHistory(_sessionStart ?? DateTime.now(), success: true);

        // Flush all accumulated slots + labeled answers to user data
        final demo = _svc.getActiveDemoUser();
        await _svc.appendEntitiesToUserData(
          userId: demo.userId,
          sessionSlots: Map<String, String>.from(_sessionSlots),
          labeledAnswers: Map<String, String>.from(_answers),
          sessionDate: _sessionStart ?? DateTime.now(),
        );
      }
    }
  }

  // ===========================================================================
  // Build
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildAppBar(),
      body: TabBarView(
        controller: _tabCtrl,
        children: [_buildChatTab(), _buildHistoryTab()],
      ),
    );
  }

  // ── App bar ────────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar() {
    final (String statusText, Color statusColor) = switch (_state) {
      _DialogueState.inDigression => ('side chat', _teal),
      _DialogueState.inDepth => ('going deeper…', _purple),
      _ when _loading => ('analysing…', Colors.orange),
      _ when _pandaTyping => ('typing…', Colors.orange),
      _DialogueState.free => ('free chat', _purple),
      _ => ('online', Colors.green),
    };

    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0.5,
      automaticallyImplyLeading: false,
      title: Column(children: [
        const Text('Panda',
            style:
                TextStyle(color: _ink, fontSize: 17, fontWeight: FontWeight.bold)),
        Text(statusText,
            style: TextStyle(color: statusColor, fontSize: 12)),
      ]),
      centerTitle: true,
      bottom: TabBar(
        controller: _tabCtrl,
        tabs: const [Tab(text: 'Chat'), Tab(text: 'History')],
        labelColor: _purple,
        unselectedLabelColor: Colors.grey,
        indicatorColor: _purple,
      ),
      actions: [
        if (!_loading && _error == null)
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.grey),
            tooltip: 'New session',
            onPressed: _loadSession,
          ),
        IconButton(
          icon: const Icon(Icons.info_outline, color: Colors.blueAccent),
          tooltip: 'Data Safety',
          onPressed: _showSafetyDialog,
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  // ── Chat tab ───────────────────────────────────────────────────────────────

  Widget _buildChatTab() {
    return Column(children: [
      _buildPathStrip(),
      Expanded(child: _buildChatArea()),
      _buildInputArea(),
    ]);
  }

  // ── Progress / state strip ─────────────────────────────────────────────────

  Widget _buildPathStrip() {
    if (_loading || _sessionComplete) return const SizedBox.shrink();

    final total = _questionQueue.length;
    final done = _qIdx.clamp(0, total);
    final progress = total > 0 ? done / total : 0.0;

    Color stripColor;
    IconData stripIcon;
    String stripLabel;

    switch (_state) {
      case _DialogueState.inDigression:
        stripColor = _teal;
        stripIcon = Icons.alt_route_rounded;
        stripLabel = 'side chat — path paused';
      case _DialogueState.inDepth:
        stripColor = _purple.withOpacity(0.7);
        stripIcon = Icons.layers_rounded;
        stripLabel = 'going deeper ($done/$total)';
      default:
        stripColor = _purple;
        stripIcon = Icons.linear_scale_rounded;
        stripLabel = total > 0 ? '$done / $total questions' : '';
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      color: stripColor.withOpacity(0.07),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      child: Row(children: [
        Icon(stripIcon, size: 13, color: stripColor),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: Colors.black.withOpacity(0.07),
              valueColor: AlwaysStoppedAnimation<Color>(stripColor),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(stripLabel,
            style: TextStyle(
                fontSize: 11,
                color: stripColor,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }

  // ── Chat area ──────────────────────────────────────────────────────────────

  Widget _buildChatArea() {
    if (_loading && _turns.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _avatar(),
          const SizedBox(height: 20),
          const TypingIndicator(),
          const SizedBox(height: 14),
          const Text('Panda is analysing your data…',
              style: TextStyle(color: Colors.black45, fontSize: 14)),
        ]),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.black26),
            const SizedBox(height: 16),
            Text(_error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _loadSession,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _purple,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
              ),
            ),
          ]),
        ),
      );
    }

    final showChips = !_pandaTyping &&
        !_sessionComplete &&
        _state != _DialogueState.inDigression &&
        _currentQ != null &&
        _currentQ!.options.isNotEmpty;
    final showDepthHint = !_pandaTyping &&
        _state == _DialogueState.inDepth &&
        _currentQ != null;
    final showDone = _sessionComplete;

    return SafeArea(
      bottom: false,
      child: ListView.builder(
        controller: _scrollCtrl,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        itemCount: _turns.length +
            (_pandaTyping ? 1 : 0) +
            (showChips ? 1 : 0) +
            (showDepthHint ? 1 : 0) +
            (showDone ? 1 : 0),
        itemBuilder: (context, i) {
          if (i < _turns.length) {
            final t = _turns[i];
            return t.role == _Role.user
                ? _userBubble(t.text)
                : _assistantBubble(t.text, kind: t.kind, recs: t.recs);
          }
          int off = _turns.length;
          if (_pandaTyping && i == off) return _typingBubble();
          if (_pandaTyping) off++;
          if (showChips && i == off) return _chipRow(_currentQ!);
          if (showChips) off++;
          if (showDepthHint && i == off) return _depthHintRow();
          if (showDepthHint) off++;
          if (showDone && i == off) return _doneCard();
          return const SizedBox.shrink();
        },
      ),
    );
  }

  // ── Bubbles ────────────────────────────────────────────────────────────────

  Widget _assistantBubble(String text, {_TurnKind kind = _TurnKind.normal, List<PandaRec> recs = const []}) {
    Color bg;
    Color border;
    Widget? badge;

    switch (kind) {
      case _TurnKind.digression:
        bg = _teal.withOpacity(0.07);
        border = _teal.withOpacity(0.25);
        badge = _kindBadge(Icons.alt_route_rounded, 'side chat', _teal);
      case _TurnKind.depth:
        bg = _purple.withOpacity(0.05);
        border = _purple.withOpacity(0.18);
        badge = _kindBadge(Icons.layers_rounded, 'deeper', _purple);
      case _TurnKind.recommend:
        bg = Colors.white;
        border = Colors.transparent;
        badge = _kindBadge(Icons.auto_awesome_rounded, 'for you', const Color(0xFFFF8C69));
      case _TurnKind.normal:
        bg = Colors.white;
        border = Colors.transparent;
        badge = null;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The message bubble
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              _avatar(),
              const SizedBox(width: 10),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                      bottomRight: Radius.circular(20),
                      bottomLeft: Radius.circular(4),
                    ),
                    border: Border.all(color: border, width: 1.2),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 5,
                          offset: const Offset(0, 2))
                    ],
                  ),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (badge != null) ...[badge, const SizedBox(height: 6)],
                        Text(text,
                            style: const TextStyle(
                                color: Colors.black87, fontSize: 15, height: 1.45)),
                      ]),
                ),
              ),
              const SizedBox(width: 40),
            ]),
          ),
          // Rec cards — shown inline below the bubble when kind == recommend
          if (recs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 50, right: 8, bottom: 8),
              child: Column(
                children: recs.map((rec) => _RecCard(rec: rec)).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _kindBadge(IconData icon, String label, Color color) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 11, color: color.withOpacity(0.7)),
      const SizedBox(width: 4),
      Text(label,
          style: TextStyle(
              fontSize: 10,
              color: color.withOpacity(0.7),
              fontWeight: FontWeight.w600)),
    ]);
  }

  Widget _userBubble(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        const SizedBox(width: 40),
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: _purple.withOpacity(0.12),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(4),
              ),
              border: Border.all(color: _purple.withOpacity(0.2)),
            ),
            child: Text(text,
                style:
                    const TextStyle(color: _ink, fontSize: 15, height: 1.45)),
          ),
        ),
      ]),
    );
  }

  Widget _typingBubble() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        _avatar(),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
              bottomRight: Radius.circular(20),
              bottomLeft: Radius.circular(4),
            ),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 5,
                  offset: const Offset(0, 2))
            ],
          ),
          child: const TypingIndicator(),
        ),
      ]),
    );
  }

  Widget _chipRow(PandaQuestion q) {
    return Padding(
      padding: const EdgeInsets.only(left: 58, bottom: 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: q.options
            .map((opt) => GestureDetector(
                  onTap: () => _chipTap(opt),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: _purple.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _purple.withOpacity(0.25)),
                    ),
                    child: Text(opt,
                        style: const TextStyle(
                            color: _purple,
                            fontWeight: FontWeight.w600,
                            fontSize: 14)),
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _depthHintRow() {
    return Padding(
      padding: const EdgeInsets.only(left: 58, bottom: 12),
      child: Row(children: [
        Icon(Icons.layers_rounded, size: 13, color: _purple.withOpacity(0.5)),
        const SizedBox(width: 6),
        Text(
          'Keep sharing or type "done" to move on',
          style: TextStyle(
              fontSize: 12,
              color: _purple.withOpacity(0.55),
              fontStyle: FontStyle.italic),
        ),
      ]),
    );
  }

  Widget _doneCard() {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: _purple.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _purple.withOpacity(0.15)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('✅  Session complete',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _purple,
                    fontSize: 14)),
            const SizedBox(height: 4),
            Text(
                '${_answers.length} answer${_answers.length == 1 ? '' : 's'} captured'
                '${_sessionSlots.isNotEmpty ? ' · ${_sessionSlots.length} insights extracted' : ''}',
                style: const TextStyle(color: Colors.black45, fontSize: 13)),
            const SizedBox(height: 4),
            const Text('Keep chatting or start a new session.',
                style: TextStyle(color: Colors.black38, fontSize: 12)),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: _loadSession,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('New session'),
              style: TextButton.styleFrom(foregroundColor: _purple),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Input area ─────────────────────────────────────────────────────────────

  Widget _buildInputArea() {
    final bool disabled = _loading || _pandaTyping;

    String hint;
    if (_sessionComplete) {
      hint = 'Ask Panda anything 💜';
    } else if (disabled) {
      hint = 'Panda is thinking…';
    } else if (_state == _DialogueState.inDigression) {
      hint = 'Keep going — Panda is all ears…';
    } else if (_state == _DialogueState.inDepth) {
      hint = 'Tell me more, or type "done" to move on…';
    } else {
      hint = 'Answer or ask Panda anything…';
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 34),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.black12, width: 0.5)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (!_sessionComplete &&
            _state == _DialogueState.onPath &&
            _currentQ != null &&
            _currentQ!.options.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Tap a chip above or type your own answer',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _inputCtrl,
              enabled: !disabled,
              textInputAction: TextInputAction.send,
              maxLines: null,
              decoration: InputDecoration(
                hintText: hint,
                hintStyle:
                    TextStyle(color: Colors.grey.shade400, fontSize: 14),
                filled: true,
                fillColor: disabled ? Colors.grey.shade100 : _bg,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(color: Colors.grey.shade300)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(color: Colors.grey.shade300)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide:
                        const BorderSide(color: _purple, width: 1.5)),
                disabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide:
                        BorderSide(color: Colors.grey.shade200)),
              ),
              onSubmitted: disabled ? null : (_) => _submit(),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: disabled ? null : _submit,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 46,
              width: 46,
              decoration: BoxDecoration(
                color: disabled ? Colors.grey.shade300 : _purple,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.send_rounded,
                  color:
                      disabled ? Colors.grey.shade400 : Colors.white,
                  size: 20),
            ),
          ),
        ]),
      ]),
    );
  }

  // ===========================================================================
  // History tab
  // ===========================================================================

  Widget _buildHistoryTab() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Row(children: [
            const Expanded(
                child: Text('Past Sessions',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: _ink))),
            if (_history.isNotEmpty)
              TextButton(
                  onPressed: () => setState(() => _history.clear()),
                  child: const Text('Clear all',
                      style: TextStyle(color: Colors.redAccent))),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: _history.isEmpty
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                    _avatar(),
                    const SizedBox(height: 16),
                    const Text(
                        'No sessions yet.\nComplete a chat and it\'ll appear here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black45, height: 1.5)),
                  ]))
                : ListView.separated(
                    itemCount: _history.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _historyCard(_history[i]),
                  ),
          ),
        ]),
      ),
    );
  }

  Widget _historyCard(_HistoryRecord r) {
    final statusColor = r.success ? Colors.green : Colors.red;
    final duration = r.endedAt.difference(r.startedAt);
    final hasBranches = r.graphNodes.any((n) => n.isBranch);

    String _fmtDt(DateTime dt) {
      final l = dt.toLocal();
      final h12 = l.hour % 12 == 0 ? 12 : l.hour % 12;
      final min = l.minute.toString().padLeft(2, '0');
      final ap = l.hour >= 12 ? 'PM' : 'AM';
      return '${l.year}-${l.month.toString().padLeft(2,'0')}-${l.day.toString().padLeft(2,'0')}  $h12:$min $ap';
    }

    String _fmtDur(Duration d) => d.inMinutes >= 1
        ? '${d.inMinutes}m ${d.inSeconds.remainder(60)}s'
        : '${d.inSeconds}s';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.07)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding:
              const EdgeInsets.only(left: 16, right: 16, bottom: 16),
          title: Row(children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_fmtDt(r.startedAt),
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: _ink)),
                    const SizedBox(height: 3),
                    Row(children: [
                      Text(
                          '${r.answers.length} answers · ${_fmtDur(duration)}',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black45)),
                      if (hasBranches) ...[
                        const SizedBox(width: 8),
                        _badge('branched', _teal),
                      ],
                      if (r.sessionSlots.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        _badge('${r.sessionSlots.length} insights', _purple),
                      ],
                    ]),
                  ]),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.10),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: statusColor.withOpacity(0.3)),
              ),
              child: Text(r.success ? 'Complete' : 'Failed',
                  style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ),
          ]),
          children: [
            // Overall notes
            if (r.overallNotes.isNotEmpty) ...[
              _noteBox(r.overallNotes),
              const SizedBox(height: 12),
            ],
            if (!r.success && r.error != null) ...[
              Text('Error: ${r.error}',
                  style: const TextStyle(
                      color: Colors.redAccent, fontSize: 12)),
              const SizedBox(height: 12),
            ],

            // Conversation graph
            if (r.graphNodes.isNotEmpty) ...[
              const Text('Conversation Graph',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: _ink)),
              const SizedBox(height: 4),
              Row(children: [
                _GraphLegendDot(color: _purple, label: 'Main flow'),
                const SizedBox(width: 14),
                _GraphLegendDot(color: _teal, label: 'Branch'),
              ]),
              const SizedBox(height: 10),
              _ConversationGraphView(nodes: r.graphNodes),
              const SizedBox(height: 12),
            ],

            // ── Your Answers ──────────────────────────────────────────────
            // Shows each Q→A pair with an inline edit button. Editing updates
            // the record in memory and fires a mock DB write via GeminiService.
            if (r.graphNodes.isNotEmpty && r.answers.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(children: [
                const Expanded(
                  child: Text('Your Answers',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: _ink)),
                ),
                Text('tap ✏️ to correct',
                    style: TextStyle(
                        fontSize: 10,
                        color: Colors.black38,
                        fontStyle: FontStyle.italic)),
              ]),
              const SizedBox(height: 8),
              ...r.graphNodes
                  .where((n) => r.answers.containsKey(n.questionId))
                  .map((n) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: Colors.black.withOpacity(0.08)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(n.questionText,
                                          style: const TextStyle(
                                              fontSize: 11,
                                              color: Colors.black45,
                                              height: 1.35)),
                                      const SizedBox(height: 3),
                                      Text(
                                          r.answers[n.questionId] ?? '—',
                                          style: const TextStyle(
                                              fontSize: 13,
                                              color: _ink,
                                              fontWeight: FontWeight.w500)),
                                    ],
                                  ),
                                ),
                              ),
                              // Edit button
                              InkWell(
                                onTap: () => _editAnswer(
                                    record: r,
                                    questionId: n.questionId,
                                    questionText: n.questionText,
                                    currentAnswer:
                                        r.answers[n.questionId] ?? ''),
                                borderRadius: const BorderRadius.only(
                                    topRight: Radius.circular(10),
                                    bottomRight: Radius.circular(10)),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                  child: const Text('✏️',
                                      style: TextStyle(fontSize: 16)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )),
              const SizedBox(height: 4),
            ],

            // Extracted insights / filled slots
            if (r.sessionSlots.isNotEmpty) ...[
              const Text('Extracted Insights',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: _ink)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: r.sessionSlots.entries
                    .map((e) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: _teal.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: _teal.withOpacity(0.2)),
                          ),
                          child: Text('${e.key}: ${e.value}',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: _teal.withOpacity(0.9))),
                        ))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // Edit answer — dialog + mock DB write
  // ===========================================================================

  /// Opens a dialog letting the user correct a labeled answer from a past
  /// session. On confirm:
  ///   1. Updates the in-memory _HistoryRecord (instant UI refresh).
  ///   2. Calls GeminiService.updateLabeledAnswer() — a clearly commented
  ///      placeholder that prints what would be written to Firestore.
  Future<void> _editAnswer({
    required _HistoryRecord record,
    required String questionId,
    required String questionText,
    required String currentAnswer,
  }) async {
    final controller = TextEditingController(text: currentAnswer);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          const Text('✏️  ', style: TextStyle(fontSize: 20)),
          const Expanded(
              child: Text('Edit Answer',
                  style:
                      TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(questionText,
                style: const TextStyle(
                    fontSize: 13,
                    color: Colors.black54,
                    height: 1.4,
                    fontStyle: FontStyle.italic)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              minLines: 1,
              decoration: InputDecoration(
                hintText: 'Enter your corrected answer…',
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _purple.withOpacity(0.3)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _purple, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
                '⚡ Correcting your answer helps Panda learn your stress patterns more accurately.',
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.black38,
                    height: 1.4)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.black45))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _purple,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final newAnswer = controller.text.trim();
    if (newAnswer.isEmpty || newAnswer == currentAnswer) return;

    // 1. Update in-memory record (triggers UI rebuild)
    setState(() {
      record.answers[questionId] = newAnswer;
    });

    // 2. Persist via mock service call
    final demo = _svc.getActiveDemoUser();
    await _svc.updateLabeledAnswer(
      userId: demo.userId,
      sessionDate: record.startedAt,
      questionId: questionId,
      oldAnswer: currentAnswer,
      newAnswer: newAnswer,
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, color: color, fontWeight: FontWeight.w600)),
    );
  }

  Widget _noteBox(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _purple.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.psychology_outlined, size: 16, color: _purple),
        const SizedBox(width: 8),
        Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 13, color: _purple, height: 1.4))),
      ]),
    );
  }

  // ── Safety dialog ──────────────────────────────────────────────────────────

  void _showSafetyDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(children: [
          Icon(Icons.shield_outlined, color: Colors.blueAccent),
          SizedBox(width: 10),
          Text('Privacy & Safety',
              style:
                  TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ]),
        content: const Text(
            'All health insights and conversations are encrypted and private.',
            style: TextStyle(fontSize: 15, height: 1.4)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Got it',
                  style: TextStyle(
                      color: _purple, fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  // ── Recommendation card ─────────────────────────────────────────────────────

  Widget _RecCard({required PandaRec rec}) {
    final Color catColor = _recCategoryColor(rec.category);

    return GestureDetector(
      onTap: rec.deepLink != null
          ? () => _launchUrl(rec.deepLink!)
          : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: catColor.withOpacity(0.25), width: 1.3),
          boxShadow: [
            BoxShadow(
                color: catColor.withOpacity(0.07),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Row(children: [
          // Category emoji + color dot
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: catColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(rec.emoji, style: const TextStyle(fontSize: 18)),
            ),
          ),
          const SizedBox(width: 12),
          // Title + subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(rec.title,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: catColor)),
                const SizedBox(height: 2),
                Text(rec.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11.5, color: Colors.black54, height: 1.35)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Right side: duration + open arrow
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (rec.durationLabel != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: catColor.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(rec.durationLabel!,
                      style: TextStyle(
                          fontSize: 10,
                          color: catColor,
                          fontWeight: FontWeight.w600)),
                ),
              if (rec.deepLink != null) ...[
                const SizedBox(height: 4),
                Icon(Icons.open_in_new_rounded,
                    size: 14, color: catColor.withOpacity(0.5)),
              ],
            ],
          ),
        ]),
      ),
    );
  }

  Color _recCategoryColor(RecCategory cat) {
    switch (cat) {
      case RecCategory.music:     return const Color(0xFF1DB954); // Spotify green
      case RecCategory.breathing: return const Color(0xFF5B8DEF); // calm blue
      case RecCategory.movement:  return const Color(0xFFFF6B6B); // energetic red
      case RecCategory.sleep:     return const Color(0xFF9B72CF); // soft purple
      case RecCategory.focus:     return const Color(0xFFFFAA00); // amber
      case RecCategory.social:    return const Color(0xFF0ABFBC); // teal
      case RecCategory.nutrition: return const Color(0xFF4CAF50); // green
      case RecCategory.journal:   return const Color(0xFFFF8C69); // warm orange
    }
  }

  Future<void> _launchUrl(String url) async {
    html.window.open(url, '_blank');
  }

  Widget _avatar() => Container(
        width: 40,
        height: 40,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          image: DecorationImage(
              image: AssetImage('assets/panda_icon.png'),
              fit: BoxFit.contain),
        ),
      );
}

// =============================================================================
// Data models
// =============================================================================

enum _Role { user, assistant }

enum _TurnKind { normal, digression, depth, recommend }

class _Turn {
  _Turn({
    required this.role,
    required this.text,
    this.kind = _TurnKind.normal,
    this.recs = const [],
  });
  final _Role role;
  final String text;
  final _TurnKind kind;
  /// Populated when kind == recommend — the cards to display below the bubble.
  final List<PandaRec> recs;
  factory _Turn.user(String t) => _Turn(role: _Role.user, text: t);
  factory _Turn.assistant(String t, {_TurnKind kind = _TurnKind.normal, List<PandaRec> recs = const []}) =>
      _Turn(role: _Role.assistant, text: t, kind: kind, recs: recs);
}

/// A frame on the digression stack — records what we were doing when the
/// user left the predefined path.
class _DigressionFrame {
  _DigressionFrame({
    required this.pendingQuestionId,
    required this.pendingQuestionPrompt,
    required this.topic,
  });
  final String pendingQuestionId;
  final String pendingQuestionPrompt;
  final String topic;
  int turnCount = 0;
}

class _HistoryRecord {
  _HistoryRecord({
    required this.startedAt,
    required this.endedAt,
    required this.success,
    required this.turns,
    required this.answers,
    required this.overallNotes,
    required this.graphNodes,
    required this.sessionSlots,
    this.error,
  });
  final DateTime startedAt;
  final DateTime endedAt;
  final bool success;
  final String? error;
  final List<_Turn> turns;
  Map<String, String> answers; // mutable — editable from history
  final String overallNotes;
  final List<_ConvNode> graphNodes;
  final Map<String, String> sessionSlots;
}

class _ConvNode {
  _ConvNode({
    required this.questionId,
    required this.questionText,
    required this.answer,
    required this.isBranch,
    this.parentNodeId,
  });
  final String questionId;
  final String questionText;
  final String answer;
  final bool isBranch;
  final String? parentNodeId;
}

// =============================================================================
// Graph components
// =============================================================================

class _GraphLegendDot extends StatelessWidget {
  const _GraphLegendDot({required this.color, required this.label});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
          width: 10,
          height: 10,
          decoration:
              BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 5),
      Text(label,
          style: const TextStyle(fontSize: 11, color: Colors.black45)),
    ]);
  }
}

class _ConversationGraphView extends StatelessWidget {
  const _ConversationGraphView({required this.nodes});
  final List<_ConvNode> nodes;

  static const Color _mainColor = Color(0xFF7B6EF6);
  static const Color _branchColor = Color(0xFF0ABFBC);
  static const Color _edgeColor = Color(0xFFBBB8F6);
  static const Color _branchEdgeColor = Color(0xFF7DE8E6);
  static const double _nodeW = 200;
  static const double _nodeH = 64;
  static const double _hGap = 32;
  static const double _vGap = 40;

  @override
  Widget build(BuildContext context) {
    if (nodes.isEmpty) return const SizedBox.shrink();

    final mainNodes = nodes.where((n) => !n.isBranch).toList();
    final branchNodes = nodes.where((n) => n.isBranch).toList();

    final Map<String, double> nodeY = {};
    double y = 0;
    for (final n in mainNodes) {
      nodeY[n.questionId] = y;
      y += _nodeH + _vGap;
    }
    for (final b in branchNodes) {
      final py = nodeY[b.parentNodeId];
      nodeY[b.questionId] = py ?? y;
      if (py == null) y += _nodeH + _vGap;
    }

    final totalH = mainNodes.length * (_nodeH + _vGap) +
        (branchNodes.isNotEmpty ? _nodeH + _vGap : 0);

    return SizedBox(
      height: totalH,
      width: double.infinity,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _EdgePainter(
              mainNodes: mainNodes,
              branchNodes: branchNodes,
              nodeY: nodeY,
              nodeW: _nodeW,
              nodeH: _nodeH,
              hGap: _hGap,
              mainColor: _edgeColor,
              branchColor: _branchEdgeColor,
            ),
          ),
        ),
        for (final n in mainNodes)
          Positioned(
              top: nodeY[n.questionId]!,
              left: 0,
              width: _nodeW,
              child: _NodeBox(
                  node: n, color: _mainColor, nodeH: _nodeH)),
        for (final b in branchNodes)
          Positioned(
              top: nodeY[b.questionId]!,
              left: _nodeW + _hGap,
              width: _nodeW,
              child: _NodeBox(
                  node: b, color: _branchColor, nodeH: _nodeH)),
      ]),
    );
  }
}

class _NodeBox extends StatelessWidget {
  const _NodeBox(
      {required this.node, required this.color, required this.nodeH});
  final _ConvNode node;
  final Color color;
  final double nodeH;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: nodeH,
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.35), width: 1.5),
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(node.questionText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 10,
                    color: color,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 3),
            Row(children: [
              Icon(Icons.chevron_right,
                  size: 12, color: color.withOpacity(0.6)),
              const SizedBox(width: 2),
              Expanded(
                  child: Text(node.answer,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11,
                          color: Colors.black54,
                          fontWeight: FontWeight.w500))),
            ]),
          ]),
    );
  }
}

class _EdgePainter extends CustomPainter {
  _EdgePainter({
    required this.mainNodes,
    required this.branchNodes,
    required this.nodeY,
    required this.nodeW,
    required this.nodeH,
    required this.hGap,
    required this.mainColor,
    required this.branchColor,
  });

  final List<_ConvNode> mainNodes, branchNodes;
  final Map<String, double> nodeY;
  final double nodeW, nodeH, hGap;
  final Color mainColor, branchColor;

  @override
  void paint(Canvas canvas, Size size) {
    final mp = Paint()
      ..color = mainColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final bp = Paint()
      ..color = branchColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final dp = Paint()
      ..color = branchColor.withOpacity(0.6)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final mcx = nodeW / 2;
    final bcx = nodeW + hGap + nodeW / 2;

    for (int i = 0; i < mainNodes.length - 1; i++) {
      final from =
          Offset(mcx, nodeY[mainNodes[i].questionId]! + nodeH);
      final to = Offset(mcx, nodeY[mainNodes[i + 1].questionId]!);
      canvas.drawLine(from, to, mp);
      _arrowHead(canvas, mp, from, to);
    }

    for (final b in branchNodes) {
      final pid = b.parentNodeId;
      if (pid == null) continue;
      final py = nodeY[pid];
      if (py == null) continue;
      final by = nodeY[b.questionId]!;

      final from = Offset(nodeW, py + nodeH / 2);
      final to = Offset(nodeW + hGap, by + nodeH / 2);
      final cp1 = Offset(nodeW + hGap * 0.5, from.dy);
      final cp2 = Offset(nodeW + hGap * 0.5, to.dy);
      canvas.drawPath(
          Path()
            ..moveTo(from.dx, from.dy)
            ..cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, to.dx, to.dy),
          bp);
      _arrowHead(canvas, bp, cp2, to);

      final pi = mainNodes.indexWhere((n) => n.questionId == pid);
      if (pi >= 0 && pi + 1 < mainNodes.length) {
        final ry = nodeY[mainNodes[pi + 1].questionId]!;
        _dashed(canvas, dp, Offset(bcx, by + nodeH), Offset(mcx, ry));
      }
    }
  }

  void _arrowHead(Canvas c, Paint p, Offset from, Offset to) {
    final angle = (to - from).direction;
    c.drawLine(to, to + Offset.fromDirection(angle + 3.14159 - 0.4, 8), p);
    c.drawLine(to, to + Offset.fromDirection(angle + 3.14159 + 0.4, 8), p);
  }

  void _dashed(Canvas c, Paint p, Offset from, Offset to) {
    final dist = (to - from).distance;
    final dir = (to - from) / dist;
    double t = 0;
    bool draw = true;
    while (t < dist) {
      final seg = draw ? 5.0 : 4.0;
      final end = t + seg;
      if (draw) {
        c.drawLine(from + dir * t,
            from + dir * (end < dist ? end : dist), p);
      }
      t = end;
      draw = !draw;
    }
  }

  @override
  bool shouldRepaint(_EdgePainter o) => true;
}

// =============================================================================
// Typing indicator
// =============================================================================

class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});
  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with TickerProviderStateMixin {
  late List<AnimationController> _ctrls;
  late List<Animation<double>> _anims;

  @override
  void initState() {
    super.initState();
    _ctrls = List.generate(
        3,
        (_) => AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 600))
          ..repeat(reverse: true));
    _anims = _ctrls
        .map((c) => Tween<double>(begin: 0.25, end: 1.0).animate(
            CurvedAnimation(parent: c, curve: Curves.easeInOut)))
        .toList();
    for (int i = 0; i < 3; i++) {
      Timer(Duration(milliseconds: i * 180), () {
        if (mounted) _ctrls[i].forward();
      });
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        3,
        (i) => FadeTransition(
          opacity: _anims[i],
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2.5),
            height: 7,
            width: 7,
            decoration: BoxDecoration(
                color: Colors.grey.shade400, shape: BoxShape.circle),
          ),
        ),
      ),
    );
  }
}