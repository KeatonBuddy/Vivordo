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
  final Color primaryPurple = const Color(0xFF7B6EF6);
  final Color pandaBlack = const Color(0xFF2D3142);
  final Color bgWhite = const Color(0xFFF2F2F7); // iOS style grey-white
  final Color bubbleWhite = Colors.white;

  @override
  void initState() {
    super.initState();
    // Simulate thinking/typing for 2 seconds
    Timer(const Duration(milliseconds: 2000), () {
      if (mounted) setState(() => _isTyping = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgWhite,
      appBar: _buildChatAppBar(context),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: Column(
                children: [
                  // Timestamp
                  Center(
                    child: Text(
                      "Today 10:42 AM",
                      style: TextStyle(
                        color: Colors.grey.shade500, 
                        fontSize: 12, 
                        fontWeight: FontWeight.w500
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Panda Message Row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _buildMiniAvatar(),
                      const SizedBox(width: 8),
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

  PreferredSizeWidget _buildChatAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0.5,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.blueAccent),
        onPressed: () => Navigator.pop(context),
      ),
      title: Column(
        children: [
          Text("Panda", 
            style: TextStyle(color: pandaBlack, fontSize: 17, fontWeight: FontWeight.bold)
          ),
          const Text("online", 
            style: TextStyle(color: Colors.green, fontSize: 12)
          ),
        ],
      ),
      centerTitle: true,
      actions: const [
        Icon(Icons.info_outline, color: Colors.blueAccent),
        SizedBox(width: 15),
      ],
    );
  }

  // --- AVATAR ---
  Widget _buildMiniAvatar() {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(color: pandaBlack, shape: BoxShape.circle),
      child: const Center(
        child: Icon(Icons.pets_rounded, size: 18, color: Colors.white),
      ),
    );
  }

  // --- MESSAGE BUBBLE ---
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
            offset: const Offset(0, 2)
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

  // --- VERTICAL STACKED OPTIONS ---
  Widget _buildVerticalOptions() {
    return Column(
      children: [
        _optionButton("Yes, let's meditate 🧘"),
        _optionButton("Check my sleep data 🌙"),
        _optionButton("Review my goals 🎯"),
        _optionButton("I just need to vent 🗣️"),
      ],
    );
  }

  Widget _optionButton(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 40), // Indented to look like replies
      child: GestureDetector(
        onTap: () {
          // Add interaction logic here
        },
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
            style: TextStyle(
              color: primaryPurple, 
              fontWeight: FontWeight.w600, 
              fontSize: 15
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
          const Icon(Icons.add, color: Colors.blueAccent),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: bgWhite,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Text(
                "Choose an option above...",
                style: TextStyle(color: Colors.grey.shade500, fontSize: 15),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Icon(Icons.mic_none_rounded, color: Colors.grey.shade400),
        ],
      ),
    );
  }
}

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
    _controllers = List.generate(3, (index) => AnimationController(
      vsync: this, duration: const Duration(milliseconds: 600))..repeat(reverse: true));

    _animations = _controllers.map((c) => Tween<double>(begin: 0.2, end: 1.0)
      .animate(CurvedAnimation(parent: c, curve: Curves.easeInOut))).toList();

    for (int i = 0; i < _controllers.length; i++) {
      Timer(Duration(milliseconds: i * 200), () => _controllers[i].forward());
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
          margin: const EdgeInsets.symmetric(horizontal: 2),
          height: 6, width: 6,
          decoration: BoxDecoration(color: Colors.grey.shade400, shape: BoxShape.circle),
        ),
      )),
    );
  }
}