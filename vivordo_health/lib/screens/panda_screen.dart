import 'dart:async';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

// --- MODEL ---

enum _Role { ai, user }

class _Message {
  final int id;
  final _Role role;
  final String text;
  const _Message({required this.id, required this.role, required this.text});
}

// --- SCREEN ---

class PandaScreen extends StatefulWidget {
  const PandaScreen({super.key});

  @override
  State<PandaScreen> createState() => _PandaScreenState();
}

class _PandaScreenState extends State<PandaScreen> {
  static const Color accentPurple = Color(0xFF7B6EF6);
  static const Color bgColor = Color(0xFFF2F2F7);
  static const Color textDark = Color(0xFF1C1C1E);
  static const Color textGrey = Color(0xFF8E8E93);

  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isAiTyping = false;

  String _getFirstName() {
    final user = FirebaseAuth.instance.currentUser;
    final displayName = user?.displayName ?? 'Alex';
    return displayName.split(' ').first;
  }

  late List<_Message> _messages;

  @override
  void initState() {
    super.initState();
    _messages = [
      _Message(
        id: 0,
        role: _Role.ai,
        text:
            'Hey ${_getFirstName()}! \u{1F44B} Based on your data today, your stress is low and your HRV is strong. This is a great day to tackle challenging tasks or have meaningful conversations. Want me to suggest some availability windows for tonight?',
      ),
    ];
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  static const Map<String, String> _presetResponses = {
    "How's my stress trend this week?":
        "Your stress has been trending down \u{1F4C9} \u2014 averaging 52 this week, which is 8% lower than last week. Tuesday was your peak day at 72. I'd recommend keeping Tuesdays lighter if possible.",
    "When should I schedule calls?":
        "Based on your patterns, your best windows today are:\n\n\u{1F7E2} 12:30\u20131:00 PM (low stress)\n\u{1F7E2} 6:00\u20137:30 PM (post-workout calm)\n\u{1F7E1} 9:30\u201310:30 PM (winding down)\n\nI'd recommend the 6 PM slot for important conversations.",
    "Any burnout risk?":
        "Your burnout risk is currently LOW \u2705. Your sleep consistency has improved and your weekend recovery pattern is healthy. Keep an eye on Tuesday stress spikes though \u2014 two consecutive high-stress Tuesdays could shift this to moderate.",
    "Suggest a message for my partner":
        "Here's a suggestion based on your current state:\n\n\u{1F4AC} \"Hey! Having a good day \u2014 want to FaceTime around 6:30 tonight? I should be free and feeling pretty relaxed by then.\"",
  };

  void _sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    setState(() {
      _messages.add(_Message(id: DateTime.now().millisecondsSinceEpoch, role: _Role.user, text: trimmed));
      _isAiTyping = true;
    });
    _inputController.clear();
    _scrollToBottom();

    String aiResponse;

    if (_presetResponses.containsKey(trimmed)) {
      // Use preset response with a short delay like the React version
      await Future.delayed(const Duration(milliseconds: 1000));
      aiResponse = _presetResponses[trimmed]!;
    } else {
      // Use Firebase AI for custom inputs
      try {
        final model = FirebaseAI.googleAI().generativeModel(model: 'gemini-2.5-flash');
        final prompt = [
          Content.text(
            'You are a health AI assistant called Panda. The user is ${_getFirstName()}. '
            'Keep responses short (2-4 sentences), warm, and focused on stress, sleep, HRV, and wellbeing. '
            'User says: $trimmed',
          )
        ];
        final response = await model.generateContent(prompt);
        aiResponse = response.text ??
            "That's a great question! Based on your recent data, your overall wellbeing has been improving steadily. Would you like me to dive deeper into any specific area?";
      } catch (_) {
        aiResponse =
            "That's a great question! Based on your recent data, I can see some interesting patterns. Your overall wellbeing has been improving steadily. Would you like me to dive deeper into any specific area?";
      }
    }

    if (mounted) {
      setState(() {
        _isAiTyping = false;
        _messages.add(_Message(id: DateTime.now().millisecondsSinceEpoch + 1, role: _Role.ai, text: aiResponse));
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 120), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showPrivacyPopup() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.shield_outlined, color: Color(0xFF7B6EF6)),
            SizedBox(width: 10),
            Text('Privacy & Safety', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          'Your data is safe. All health insights and conversations are encrypted and private.',
          style: TextStyle(fontSize: 14, height: 1.5, color: Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it', style: TextStyle(color: Color(0xFF7B6EF6), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showQuickPrompts = _messages.length <= 1 && !_isAiTyping;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF7B6EF6), Color(0xFF9B8FF8), Color(0xFFF2F2F7)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0.0, 0.18, 0.38],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFFF2F2F7),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(28),
                      topRight: Radius.circular(28),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(28),
                      topRight: Radius.circular(28),
                    ),
                    child: Column(
                      children: [
                        Expanded(
                          child: ListView(
                            controller: _scrollController,
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                            children: [
                              ..._messages.map((m) => _buildMessageRow(m)),
                              if (_isAiTyping) _buildTypingRow(),
                              if (showQuickPrompts) _buildQuickPrompts(),
                              const SizedBox(height: 90),
                            ],
                          ),
                        ),
                        _buildInputBar(),
                        const SizedBox(height: 95),
                      ],
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

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 20),
      color: Colors.transparent,
      child: Row(
        children: [
          // Panda avatar with online dot
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.22),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withOpacity(0.35), width: 1.5),
                ),
                child: const Center(
                  child: Text('🐼', style: TextStyle(fontSize: 24)),
                ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 13,
                  height: 13,
                  decoration: BoxDecoration(
                    color: const Color(0xFF34C759),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF7B6EF6), width: 2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          // Title + status
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Panda',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      width: 6, height: 6,
                      decoration: const BoxDecoration(
                        color: Color(0xFF34C759),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Online · Your health AI',
                      style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.8)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Privacy button
          GestureDetector(
            onTap: _showPrivacyPopup,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.18),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.shield_outlined, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageRow(_Message msg) {
    final isAi = msg.role == _Role.ai;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isAi ? MainAxisAlignment.start : MainAxisAlignment.end,
        children: [
          if (isAi) ...[
            _buildAvatar(isAi: true),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
              decoration: BoxDecoration(
                color: isAi ? Colors.white : accentPurple,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isAi ? 4 : 18),
                  bottomRight: Radius.circular(isAi ? 18 : 4),
                ),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2)),
                ],
              ),
              child: Text(
                msg.text,
                style: TextStyle(
                  fontSize: 14,
                  color: isAi ? textDark : Colors.white,
                  height: 1.5,
                ),
              ),
            ),
          ),
          if (!isAi) ...[
            const SizedBox(width: 10),
            _buildAvatar(isAi: false),
          ],
        ],
      ),
    );
  }

  Widget _buildTypingRow() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAvatar(isAi: true),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(18),
              ),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2)),
              ],
            ),
            child: const TypingIndicator(),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar({required bool isAi}) {
    if (isAi) {
      return Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: accentPurple.withOpacity(0.12),
          shape: BoxShape.circle,
          border: Border.all(color: accentPurple.withOpacity(0.2)),
        ),
        child: const Center(
          child: Text('🐼', style: TextStyle(fontSize: 16)),
        ),
      );
    }
    return Container(
      width: 32,
      height: 32,
      decoration: const BoxDecoration(
        color: Color(0xFFE5E5EA),
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.person_rounded, size: 17, color: Color(0xFF8E8E93)),
    );
  }

  Widget _buildQuickPrompts() {
    const prompts = [
      ('📉', "How's my stress trend this week?"),
      ('📅', 'When should I schedule calls?'),
      ('🔥', 'Any burnout risk?'),
      ('💬', 'Suggest a message for my partner'),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SUGGESTED',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                color: textGrey, letterSpacing: 0.8),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: prompts.map(((String, String) p) => GestureDetector(
              onTap: () => _sendMessage(p.$2),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE5E5EA)),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.04),
                        blurRadius: 6, offset: const Offset(0, 2))
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(p.$1, style: const TextStyle(fontSize: 14)),
                    const SizedBox(width: 6),
                    Text(
                      p.$2,
                      style: const TextStyle(fontSize: 12,
                          fontWeight: FontWeight.w500, color: textDark),
                    ),
                  ],
                ),
              ),
            )).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 10, 16, MediaQuery.of(context).padding.bottom + 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: Color(0xFFE5E5EA), width: 1)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04),
              blurRadius: 12, offset: const Offset(0, -4))
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 44, maxHeight: 120),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFFE5E5EA)),
              ),
              child: TextField(
                controller: _inputController,
                style: const TextStyle(fontSize: 14, color: textDark),
                maxLines: null,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Ask Panda anything...',
                  hintStyle: TextStyle(fontSize: 13, color: textGrey),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                onSubmitted: _sendMessage,
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _sendMessage(_inputController.text),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF9B8FF8), Color(0xFF7B6EF6)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: accentPurple.withOpacity(0.35),
                      blurRadius: 8, offset: const Offset(0, 3))
                ],
              ),
              child: const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

// --- TYPING INDICATOR ---

class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator> with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      3,
      (i) => AnimationController(vsync: this, duration: const Duration(milliseconds: 600))
        ..repeat(reverse: true),
    );
    _animations = _controllers
        .map((c) => Tween<double>(begin: 0.2, end: 1.0).animate(CurvedAnimation(parent: c, curve: Curves.easeInOut)))
        .toList();
    for (int i = 0; i < _controllers.length; i++) {
      Timer(Duration(milliseconds: i * 180), () {
        if (mounted) _controllers[i].forward();
      });
    }
  }

  @override
  void dispose() {
    for (var c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) => FadeTransition(
        opacity: _animations[i],
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2.5),
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: const Color(0xFF7B6EF6).withOpacity(0.45 + i * 0.18), shape: BoxShape.circle),
        ),
      )),
    );
  }
}
