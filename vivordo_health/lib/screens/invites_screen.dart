import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../src/services/event_invite_service.dart';
import '../theme/vivordo_theme.dart';
import '../widgets/apple_ui.dart';
import 'circle_screen.dart' show CirclePersonAvatar;

const _purple = Color(0xFF6B5CE7);

/// When an invite happens, e.g. "Thu, Nov 12 · 6:30 – 7:30 PM".
String inviteWhen(EventInvite invite) {
  final day = DateFormat('EEE, MMM d').format(invite.start);
  if (invite.allDay) return '$day · All day';
  final time = DateFormat.jm();
  return '$day · ${time.format(invite.start)} – ${time.format(invite.end)}';
}

/// "2 going · 1 waiting · 1 can't make it", leaving out the zeros.
String inviteReplies(EventInvite invite) => [
  if (invite.count('accepted') > 0) '${invite.count('accepted')} going',
  if (invite.count('pending') > 0) '${invite.count('pending')} waiting',
  if (invite.count('declined') > 0) "${invite.count('declined')} can't make it",
].join(' · ');

/// Invites from Circle friends waiting on your answer, and the ones you
/// sent. Opened from My Day's envelope and from invite notifications.
class InvitesScreen extends StatefulWidget {
  const InvitesScreen({
    super.key,
    this.received,
    this.sent,
    this.uid,
    this.respond,
  });

  /// For tests; the invite service otherwise.
  final Stream<List<EventInvite>>? received;
  final Stream<List<EventInvite>>? sent;
  final String? uid;
  final Future<void> Function(EventInvite invite, {required bool accept})?
  respond;

  @override
  State<InvitesScreen> createState() => _InvitesScreenState();
}

class _InvitesScreenState extends State<InvitesScreen> {
  late final _received = widget.received ?? EventInviteService.watchReceived();
  late final _sent = widget.sent ?? EventInviteService.watchSent();
  late final _uid = widget.uid ?? FirebaseAuth.instance.currentUser?.uid;
  final Set<String> _busy = {};

  Future<void> _answer(EventInvite invite, bool accept) async {
    setState(() => _busy.add(invite.id));
    try {
      await (widget.respond ?? EventInviteService.respond)(
        invite,
        accept: accept,
      );
      if (mounted && accept) showToast(context, 'Added to your calendar.');
    } on NoCalendarConnected {
      if (mounted) {
        showToast(
          context,
          'Connect Google or Outlook in Settings to accept invites.',
          kind: ToastKind.error,
        );
      }
    } catch (error) {
      debugPrint('Invite answer failed: $error');
      if (mounted) {
        showToast(
          context,
          "Couldn't answer the invite. Try again.",
          kind: ToastKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(invite.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return Scaffold(
      backgroundColor: colors.page,
      body: SafeArea(
        bottom: false,
        child: StreamBuilder<List<EventInvite>>(
          stream: _received,
          builder: (context, received) => StreamBuilder<List<EventInvite>>(
            stream: _sent,
            builder: (context, sent) {
              final now = DateTime.now();
              final uid = _uid;
              final waiting = [
                for (final invite in received.data ?? const <EventInvite>[])
                  if (uid != null && invite.pendingFor(uid, now)) invite,
              ];
              final yours = [
                for (final invite in sent.data ?? const <EventInvite>[])
                  if (invite.end.isAfter(now)) invite,
              ];
              final loading = !received.hasData && !received.hasError;
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 48),
                children: [
                  Row(
                    children: [
                      IconButton.filledTonal(
                        tooltip: 'Back',
                        onPressed: () => Navigator.maybePop(context),
                        icon: const Icon(CupertinoIcons.chevron_left, size: 30),
                        style: IconButton.styleFrom(
                          backgroundColor: colors.card,
                          foregroundColor: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Invites',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 36,
                          height: 1,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (received.hasError)
                    const _Empty(
                      title: 'Couldn’t load your invites',
                      body: 'Check your connection, then reopen Invites.',
                    )
                  else if (loading)
                    const Padding(
                      padding: EdgeInsets.all(34),
                      child: Center(child: CupertinoActivityIndicator()),
                    )
                  else if (waiting.isEmpty && yours.isEmpty)
                    const _Empty(
                      title: 'No invites yet',
                      body:
                          'When a Circle friend invites you to something, it '
                          'shows up here. To invite friends, add an event and '
                          'choose them under Invite friends.',
                    )
                  else ...[
                    if (waiting.isNotEmpty) ...[
                      const _Label('Waiting for you'),
                      for (final invite in waiting)
                        _InviteCard(
                          invite: invite,
                          busy: _busy.contains(invite.id),
                          onAnswer: (accept) =>
                              unawaited(_answer(invite, accept)),
                        ),
                      const SizedBox(height: 14),
                    ],
                    if (yours.isNotEmpty) ...[
                      const _Label('You sent'),
                      for (final invite in yours) _SentCard(invite: invite),
                    ],
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w800,
        color: context.vivordoColors.textSecondary,
      ),
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.vivordoColors.card,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.black.withValues(alpha: .07)),
    ),
    child: child,
  );
}

class _InviteCard extends StatelessWidget {
  const _InviteCard({
    required this.invite,
    required this.busy,
    required this.onAnswer,
  });

  final EventInvite invite;
  final bool busy;
  final ValueChanged<bool> onAnswer;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CirclePersonAvatar(
                name: invite.fromName,
                uid: invite.fromUid,
                size: 34,
                photoUrl: invite.fromPhotoUrl,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: invite.fromName,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const TextSpan(text: ' invited you'),
                    ],
                  ),
                  style: TextStyle(color: colors.textSecondary, fontSize: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            invite.title,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            inviteWhen(invite),
            style: TextStyle(color: colors.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: busy ? null : () => onAnswer(false),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                    backgroundColor: colors.cardMuted,
                    foregroundColor: colors.textPrimary,
                    shape: buttonShape,
                  ),
                  child: const Text('Decline'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: busy ? null : () => onAnswer(true),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                    backgroundColor: _purple,
                    foregroundColor: Colors.white,
                    shape: buttonShape,
                  ),
                  child: busy
                      ? const CupertinoActivityIndicator(color: Colors.white)
                      : const Text(
                          'Accept',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'Accepting adds it to your calendar',
              style: TextStyle(color: colors.textSecondary, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _SentCard extends StatelessWidget {
  const _SentCard({required this.invite});
  final EventInvite invite;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            invite.title,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            inviteWhen(invite),
            style: TextStyle(color: colors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Text(
            inviteReplies(invite),
            style: TextStyle(color: colors.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 12),
      child: Column(
        children: [
          Icon(CupertinoIcons.envelope, size: 40, color: colors.textSecondary),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textSecondary, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

/// My Day's envelope: opens Invites, with a badge while invites wait on you.
class InvitesButton extends StatefulWidget {
  const InvitesButton({super.key, this.pendingCount});

  /// For tests; the invite service otherwise.
  final Stream<int>? pendingCount;

  @override
  State<InvitesButton> createState() => _InvitesButtonState();
}

class _InvitesButtonState extends State<InvitesButton> {
  late final _count =
      widget.pendingCount ?? EventInviteService.watchPendingCount();

  @override
  Widget build(BuildContext context) => StreamBuilder<int>(
    stream: _count,
    builder: (context, snapshot) {
      final count = snapshot.data ?? 0;
      return IconButton(
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const InvitesScreen())),
        tooltip: count == 0 ? 'Invites' : 'Invites, $count waiting',
        icon: Badge(
          isLabelVisible: count > 0,
          label: Text('$count'),
          backgroundColor: const Color(0xFFC0392B),
          child: const Icon(CupertinoIcons.envelope, color: _purple),
        ),
      );
    },
  );
}
