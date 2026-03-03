import 'package:flutter/material.dart';
import 'dart:async';
import '../src/services/gemini_service.dart';

// ---------------------------------------------------------------------------
// PandaScreen
// ---------------------------------------------------------------------------

class PandaScreen extends StatefulWidget {
  const PandaScreen({super.key});

  @override
  State<PandaScreen> createState() => _PandaScreenState();
}

class _PandaScreenState extends State<PandaScreen> {
  // ---- Theme ----
  static const Color primaryPurple = Color(0xFF7B6EF6);
  static const Color pandaBlack = Color(0xFF2D3142);
  static const Color bgWhite = Color(0xFFF2F2F7);
  static const Color bubbleWhite = Colors.white;

  // ---- Service ----
  final GeminiService _service = GeminiService();

  // ---- Session state ----
  PandaSessionData? _session;
  bool _loading = true;
  String? _error;

  // ---- Chat state ----
  final List<_ChatTurn> _turns = [];
  int _questionIndex = 0;
  final Map<String, String> _answers = {};
  bool _sessionComplete = false;

  // ---- Input ----
  final TextEditingController _otherController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // ---- Typing indicator ----
  bool _pandaTyping = false;

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  @override
  void dispose() {
    _otherController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ---- Load Gemini session ----

  Future<void> _loadSession() async {
    setState(() {
      _loading = true;
      _error = null;
      _turns.clear();
      _answers.clear();
      _questionIndex = 0;
      _sessionComplete = false;
      _session = null;
    });

    try {
      final session = await _service
          .analyzePandaSession()
          .timeout(const Duration(seconds: 90));

      if (!mounted) return;
      setState(() {
        _session = session;
        _loading = false;
      });

      // Show Panda's opener after a short typing delay
      await _pandaSay(session.openerMessage);

      // Then ask the first question (if any)
      if (session.questions.isNotEmpty) {
        await _pandaSay(session.questions.first.prompt);
      } else {
        _sessionComplete = true;
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Took too long to respond. Tap retry to try again.";
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Something went wrong: $e";
      });
    }
  }

  // ---- Chat helpers ----

  /// Appends a Panda message with a typing animation delay.
  Future<void> _pandaSay(String text, {int typingMs = 1200}) async {
    if (!mounted) return;
    setState(() => _pandaTyping = true);
    _scrollToBottom();

    await Future.delayed(Duration(milliseconds: typingMs));

    if (!mounted) return;
    setState(() {
      _pandaTyping = false;
      _turns.add(_ChatTurn.assistant(text));
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    });
  }

  // ---- Answer handling ----

  Future<void> _answerWithOption(String option) async {
    final session = _session;
    if (session == null || _sessionComplete || _pandaTyping) return;

    final currentQ = session.questions[_questionIndex];

    // Record user turn
    setState(() {
      _turns.add(_ChatTurn.user(option));
      _answers[currentQ.questionId] = option;
      _questionIndex++;
    });
    _scrollToBottom();

    // Advance or wrap up
    if (_questionIndex < session.questions.length) {
      await _pandaSay(session.questions[_questionIndex].prompt);
    } else {
      await _pandaSay(
        "Thanks so much! 💜 I've noted that for you. Understanding your patterns helps me support you better.",
        typingMs: 1000,
      );
      if (!mounted) return;
      setState(() => _sessionComplete = true);
    }
  }

  Future<void> _answerWithOtherText() async {
    final text = _otherController.text.trim();
    if (text.isEmpty) return;
    _otherController.clear();
    await _answerWithOption(text);
  }

  // ---- Privacy popup ----

  void _showSafetyPopup() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.shield_outlined, color: Colors.blueAccent),
            SizedBox(width: 10),
            Text(
              "Privacy & Safety",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: const Text(
          "Your data is safe in the chatbot. All health insights and conversations are encrypted and private.",
          style: TextStyle(fontSize: 15, height: 1.4, color: Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              "Got it",
              style: TextStyle(
                  color: primaryPurple, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  // ---- Build ----

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgWhite,
      appBar: _buildChatAppBar(),
      body: Column(
        children: [
          Expanded(child: _buildChatArea()),
          _buildBottomInputArea(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildChatAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0.5,
      automaticallyImplyLeading: false,
      title: Column(
        children: [
          const Text(
            "Panda",
            style: TextStyle(
                color: pandaBlack,
                fontSize: 17,
                fontWeight: FontWeight.bold),
          ),
          Text(
            _loading ? "thinking..." : "online",
            style: TextStyle(
              color: _loading ? Colors.orange : Colors.green,
              fontSize: 12,
            ),
          ),
        ],
      ),
      centerTitle: true,
      actions: [
        if (!_loading && _error == null)
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.grey),
            tooltip: "Restart conversation",
            onPressed: _loadSession,
          ),
        IconButton(
          icon: const Icon(Icons.info_outline, color: Colors.blueAccent),
          tooltip: "Data Safety",
          onPressed: _showSafetyPopup,
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildChatArea() {
    if (_loading && _turns.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildMiniAvatar(),
            const SizedBox(height: 20),
            const TypingIndicator(),
            const SizedBox(height: 14),
            const Text(
              "Panda is analysing your data…",
              style: TextStyle(color: Colors.black45, fontSize: 14),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.black26),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _loadSession,
                icon: const Icon(Icons.refresh),
                label: const Text("Retry"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryPurple,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      bottom: false,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        // turns + optional typing indicator + optional option chips
        itemCount: _turns.length +
            (_pandaTyping ? 1 : 0) +
            (_shouldShowOptions ? 1 : 0) +
            (_sessionComplete ? 1 : 0),
        itemBuilder: (context, index) {
          // Chat turns
          if (index < _turns.length) {
            final turn = _turns[index];
            return turn.role == _ChatRole.assistant
                ? _buildAssistantBubble(turn.text)
                : _buildUserBubble(turn.text);
          }

          int offset = _turns.length;

          // Typing indicator
          if (_pandaTyping && index == offset) {
            return _buildTypingBubble();
          }
          if (_pandaTyping) offset++;

          // Option chips (shown after Panda's last question bubble settles)
          if (_shouldShowOptions && index == offset) {
            return _buildOptionChips();
          }
          if (_shouldShowOptions) offset++;

          // Done card
          if (_sessionComplete && index == offset) {
            return _buildDoneCard();
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }

  bool get _shouldShowOptions {
    if (_pandaTyping || _sessionComplete) return false;
    final session = _session;
    if (session == null) return false;
    if (_questionIndex >= session.questions.length) return false;
    final q = session.questions[_questionIndex];
    return q.options.isNotEmpty;
  }

  // ---- Bubble widgets ----

  Widget _buildAssistantBubble(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _buildMiniAvatar(),
          const SizedBox(width: 10),
          Flexible(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: bubbleWhite,
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
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                text,
                style: const TextStyle(
                    color: Colors.black87, fontSize: 15, height: 1.45),
              ),
            ),
          ),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _buildUserBubble(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          const SizedBox(width: 40),
          Flexible(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: primaryPurple.withOpacity(0.12),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(4),
                ),
                border: Border.all(color: primaryPurple.withOpacity(0.2)),
              ),
              child: Text(
                text,
                style: const TextStyle(
                    color: pandaBlack, fontSize: 15, height: 1.45),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingBubble() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _buildMiniAvatar(),
          const SizedBox(width: 10),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: bubbleWhite,
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
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const TypingIndicator(),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionChips() {
    final session = _session!;
    final q = session.questions[_questionIndex];

    return Padding(
      padding: const EdgeInsets.only(left: 58, bottom: 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: q.options.map((opt) {
          return GestureDetector(
            onTap: () => _answerWithOption(opt),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: primaryPurple.withOpacity(0.10),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: primaryPurple.withOpacity(0.25)),
              ),
              child: Text(
                opt,
                style: const TextStyle(
                  color: primaryPurple,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDoneCard() {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: primaryPurple.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: primaryPurple.withOpacity(0.15)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "✅  Labeling complete",
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: primaryPurple,
                    fontSize: 14),
              ),
              const SizedBox(height: 6),
              Text(
                "${_answers.length} answer${_answers.length == 1 ? '' : 's'} captured",
                style:
                    const TextStyle(color: Colors.black45, fontSize: 13),
              ),
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: _loadSession,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text("Start new conversation"),
                style: TextButton.styleFrom(foregroundColor: primaryPurple),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- Bottom input bar ----

  Widget _buildBottomInputArea() {
    final bool showInput = !_loading &&
        _error == null &&
        !_sessionComplete &&
        !_pandaTyping;

    // If options are shown, show a free-text "other" option
    final bool showTextField = showInput;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 34),
      decoration: const BoxDecoration(
        color: Colors.white,
        border:
            Border(top: BorderSide(color: Colors.black12, width: 0.5)),
      ),
      child: showTextField
          ? Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _otherController,
                    decoration: InputDecoration(
                      hintText: "Type your own answer…",
                      hintStyle: TextStyle(color: Colors.grey.shade400),
                      filled: true,
                      fillColor: bgWhite,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide:
                            const BorderSide(color: primaryPurple, width: 1.5),
                      ),
                    ),
                    onSubmitted: (_) => _answerWithOtherText(),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _answerWithOtherText,
                  child: Container(
                    height: 46,
                    width: 46,
                    decoration: BoxDecoration(
                      color: primaryPurple,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.send_rounded,
                        color: Colors.white, size: 20),
                  ),
                ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: bgWhite,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Text(
                      _loading
                          ? "Panda is thinking…"
                          : _sessionComplete
                              ? "Conversation complete 🎉"
                              : "Choose an option above…",
                      style: TextStyle(
                          color: Colors.grey.shade500, fontSize: 15),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  // ---- Avatar ----

  Widget _buildMiniAvatar() {
    return Container(
      width: 40,
      height: 40,
      decoration: const BoxDecoration(
        color: Colors.transparent,
        shape: BoxShape.circle,
        image: DecorationImage(
          image: AssetImage('assets/panda_icon.png'),
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chat data models (local to PandaScreen)
// ---------------------------------------------------------------------------

enum _ChatRole { user, assistant }

class _ChatTurn {
  _ChatTurn({required this.role, required this.text});

  final _ChatRole role;
  final String text;

  factory _ChatTurn.user(String text) =>
      _ChatTurn(role: _ChatRole.user, text: text);
  factory _ChatTurn.assistant(String text) =>
      _ChatTurn(role: _ChatRole.assistant, text: text);
}

// ---------------------------------------------------------------------------
// Typing indicator (three bouncing dots)
// ---------------------------------------------------------------------------

class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      3,
      (i) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 600),
      )..repeat(reverse: true),
    );
    _animations = _controllers
        .map((c) => Tween<double>(begin: 0.25, end: 1.0).animate(
              CurvedAnimation(parent: c, curve: Curves.easeInOut),
            ))
        .toList();

    for (int i = 0; i < _controllers.length; i++) {
      Timer(Duration(milliseconds: i * 180), () {
        if (mounted) _controllers[i].forward();
      });
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        3,
        (i) => FadeTransition(
          opacity: _animations[i],
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2.5),
            height: 7,
            width: 7,
            decoration: BoxDecoration(
              color: Colors.grey.shade400,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}