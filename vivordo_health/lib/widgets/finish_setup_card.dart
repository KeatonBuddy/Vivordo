import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../screens/onboarding_flow_screen.dart';
import '../theme/vivordo_theme.dart';

/// Home's "Finish setting up" card: after the short onboarding, offers the
/// optional [setupSteps] until they're done or dismissed (`setupPending` on
/// the user doc). Everything in them is also in Settings.
class FinishSetupCard extends StatefulWidget {
  const FinishSetupCard({super.key});

  @override
  State<FinishSetupCard> createState() => _FinishSetupCardState();
}

class _FinishSetupCardState extends State<FinishSetupCard> {
  Map<String, dynamic>? _user;

  DocumentReference<Map<String, dynamic>>? get _ref {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid == null
        ? null
        : FirebaseFirestore.instance.collection('users').doc(uid);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  // Read once: only this card and the setup run change `setupPending`.
  Future<void> _load() async {
    try {
      final user = (await _ref?.get())?.data();
      if (mounted) setState(() => _user = user);
    } catch (error) {
      debugPrint('Finish setup card: $error');
    }
  }

  Future<void> _dismiss() async {
    setState(() => _user = null);
    try {
      await _ref?.set({'setupPending': false}, SetOptions(merge: true));
    } catch (error) {
      debugPrint('Finish setup dismiss failed: $error');
    }
  }

  Future<void> _open() async {
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (route) => OnboardingFlowScreen(
          userDoc: _user,
          setup: true,
          onFinished: () async => Navigator.of(route).pop(),
        ),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_user?['setupPending'] != true) return const SizedBox.shrink();
    final colors = context.vivordoColors;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(16, 14, 6, 16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Finish setting up',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Add your calendar, sleep times and notifications. '
                        'About 2 minutes.',
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.35,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Not now',
                onPressed: _dismiss,
                icon: Icon(
                  CupertinoIcons.xmark,
                  size: 18,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: FilledButton(
              onPressed: _open,
              style: FilledButton.styleFrom(
                backgroundColor: VivordoTheme.brand,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(46),
                shape: const StadiumBorder(),
              ),
              child: const Text(
                'Continue',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
