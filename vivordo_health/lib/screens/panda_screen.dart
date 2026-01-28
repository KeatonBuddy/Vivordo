import 'package:flutter/material.dart';
import 'dart:async';

class PandaScreen extends StatefulWidget {
  const PandaScreen({super.key});

  @override
  State<PandaScreen> createState() => _PandaScreenState();
}

class _PandaScreenState extends State<PandaScreen> {
  bool _isTyping = true;

  // Theme Colors
  static const Color primaryPurple = Color(0xFF7B6EF6);
  static const Color pandaBlack = Color(0xFF2D3142);
  static const Color bgWhite = Color(0xFFF2F2F7);
  static const Color bubbleWhite = Colors.white;

  @override
  void initState() {
    super.initState();
    // Simulate thinking/typing for 2 seconds
    Timer(const Duration(milliseconds: 2000), () {
      if (mounted) setState(() => _isTyping = false);
    });
  }

  // --- PRIVACY POPUP ---
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
            Text("Privacy & Safety", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
              style: TextStyle(color: primaryPurple, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgWhite,
      appBar: _buildChatAppBar(),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _buildMiniAvatar(),
                      const SizedBox(width: 10),
                      Flexible(child: _buildMessageBubble()),
                    ],
                  ),
                  if (!_isTyping) ...[
                    const SizedBox(height: 30),
                    _buildVerticalOptions(),
                  ],
                ],
              ),
            ),
          ),
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
      title: const Column(
        children: [
          Text(
            "Panda",
            style: TextStyle(color: pandaBlack, fontSize: 17, fontWeight: FontWeight.bold),
          ),
          Text(
            "online",
            style: TextStyle(color: Colors.green, fontSize: 12),
          ),
        ],
      ),
      centerTitle: true,
      actions: [
        IconButton(
          icon: const Icon(Icons.info_outline, color: Colors.blueAccent),
          tooltip: "Data Safety",
          onPressed: _showSafetyPopup, 
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildMiniAvatar() {
    return Container(
      width: 48,
      height: 48,
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

  Widget _buildMessageBubble() {
    return Container(
      padding: const EdgeInsets.all(16),
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
      child: _isTyping
          ? const TypingIndicator()
          : const Text(
              "Hi Sarah! 🌿 I noticed your stress levels are climbing. Want to take a 2-minute break with me?",
              style: TextStyle(color: Colors.black87, fontSize: 16, height: 1.4),
            ),
    );
  }

  Widget _buildVerticalOptions() {
    return Column(
      children: [
        _optionButton("Yes, let's meditate 🧘"),
        _optionButton("Check my sleep data 🌙"),
        _optionButton("Review my goals 🎯"),
      ],
    );
  }

  Widget _optionButton(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 40),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
          },
          borderRadius: BorderRadius.circular(25),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
            decoration: BoxDecoration(
              color: primaryPurple.withOpacity(0.1),
              borderRadius: BorderRadius.circular(25),
              border: Border.all(color: primaryPurple.withOpacity(0.2)),
            ),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: primaryPurple,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomInputArea() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 34),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.black12, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: bgWhite,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Text(
                "Choose an option above...",
                style: TextStyle(color: Colors.grey.shade500, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --- TYPING INDICATOR HELPER ---

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
      (index) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 600),
      )..repeat(reverse: true),
    );

    _animations = _controllers
        .map((c) => Tween<double>(begin: 0.2, end: 1.0).animate(
              CurvedAnimation(parent: c, curve: Curves.easeInOut),
            ))
        .toList();

    for (int i = 0; i < _controllers.length; i++) {
      Timer(Duration(milliseconds: i * 200), () {
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
      children: List.generate(
        3,
        (i) => FadeTransition(
          opacity: _animations[i],
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            height: 6,
            width: 6,
            decoration: BoxDecoration(color: Colors.grey.shade400, shape: BoxShape.circle),
          ),
        ),
      ),
    );
  }
}