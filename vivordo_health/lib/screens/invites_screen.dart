import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../src/services/event_invite_service.dart';
import '../src/utils/invite_fit.dart';
import '../theme/vivordo_theme.dart';
import '../widgets/apple_ui.dart';
import 'circle_screen.dart' show CirclePersonAvatar;

const _purple = Color(0xFF6B5CE7);

/// When an invite happens, e.g. "Thu, Nov 12 · 6:30 – 7:30 PM".
/// A series reads "Every week on Wed · 6:00 PM – 7:00 PM", plus when it
/// starts if that's still ahead.
String inviteWhen(EventInvite invite, {DateTime? now}) {
  final time = DateFormat.jm();
  final hours = invite.allDay
      ? 'All day'
      : '${time.format(invite.start)} – ${time.format(invite.end)}';
  final day = DateFormat('EEE, MMM d').format(invite.start);
  if (invite.recurrence == null) return '$day · $hours';
  final starts = invite.start.isAfter(now ?? DateTime.now())
      ? ' · from $day'
      : '';
  return '${invite.repeat.describe()} · $hours$starts';
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
    this.loadFit,
    this.undoDecline,
  });

  /// For tests; the invite service otherwise.
  final Stream<List<EventInvite>>? received;
  final Stream<List<EventInvite>>? sent;
  final String? uid;
  final Future<void> Function(EventInvite invite, {required bool accept})?
  respond;
  final Future<InviteFit?> Function(EventInvite invite)? loadFit;
  final Future<void> Function(EventInvite invite)? undoDecline;

  @override
  State<InvitesScreen> createState() => _InvitesScreenState();
}

class _InvitesScreenState extends State<InvitesScreen> {
  late final _received = widget.received ?? EventInviteService.watchReceived();
  late final _sent = widget.sent ?? EventInviteService.watchSent();
  late final _uid = widget.uid ?? FirebaseAuth.instance.currentUser?.uid;

  /// Invite id → the answer being sent (true = accept).
  final Map<String, bool> _answering = {};

  /// Each waiting invite's fit, loaded once rather than on every rebuild.
  final Map<String, Future<InviteFit?>> _fits = {};

  // Screens given test streams don't reach for the real calendar.
  Future<InviteFit?> _loadFit(EventInvite invite) =>
      widget.loadFit?.call(invite) ??
      (widget.received == null
          ? EventInviteService.fitFor(invite)
          : Future.value());

  @override
  void initState() {
    super.initState();
    // A change or cancellation push opens here: bring your calendar in line.
    if (widget.received == null) unawaited(EventInviteService.syncCopies());
  }

  Future<void> _backOut(EventInvite invite) async {
    final confirmed = await confirmAction(
      context,
      title: "Can't make it?",
      message:
          'This takes “${invite.title}” off your calendar and lets '
          '${invite.fromName} know.',
      confirmLabel: "Can't make it",
    );
    if (confirmed && mounted) await _answer(invite, false);
  }

  Future<void> _undoDecline(EventInvite invite) async {
    try {
      await (widget.undoDecline ?? EventInviteService.undoDecline)(invite);
    } catch (error) {
      debugPrint('Invite decline not undone: $error');
      if (mounted) {
        showToast(context, "Couldn't undo. Try again.", kind: ToastKind.error);
      }
    }
  }

  Future<void> _answer(EventInvite invite, bool accept) async {
    setState(() => _answering[invite.id] = accept);
    try {
      await (widget.respond ?? EventInviteService.respond)(
        invite,
        accept: accept,
      );
      if (mounted && accept) showToast(context, 'Added to your calendar.');
      if (mounted && !accept) {
        final wasGoing = invite.responses[_uid] == 'accepted';
        showToast(
          context,
          wasGoing
              ? 'Taken off your calendar.'
              : 'Declined. ${invite.fromName} will be told.',
          actionLabel: 'Undo',
          // Back to how it was: going again (back in your calendar) or
          // waiting for an answer.
          onAction: () => unawaited(
            wasGoing ? _answer(invite, true) : _undoDecline(invite),
          ),
        );
      }
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
      if (mounted) setState(() => _answering.remove(invite.id));
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
              final going = [
                for (final invite in received.data ?? const <EventInvite>[])
                  if (uid != null && invite.goingFor(uid, now)) invite,
              ];
              final notGoing = [
                for (final invite in received.data ?? const <EventInvite>[])
                  if (uid != null && invite.notGoingFor(uid, now)) invite,
              ];
              final yours = [
                for (final invite in sent.data ?? const <EventInvite>[])
                  if (invite.activeUntil.isAfter(now)) invite,
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
                  else if (waiting.isEmpty &&
                      going.isEmpty &&
                      notGoing.isEmpty &&
                      yours.isEmpty)
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
                          fit: _fits[invite.id] ??= _loadFit(invite),
                          answering: _answering[invite.id],
                          onAnswer: (accept) =>
                              unawaited(_answer(invite, accept)),
                        ),
                      const SizedBox(height: 14),
                    ],
                    if (going.isNotEmpty) ...[
                      const _Label('Going'),
                      for (final invite in going)
                        _GoingCard(
                          invite: invite,
                          busy: _answering.containsKey(invite.id),
                          onBackOut: () => unawaited(_backOut(invite)),
                        ),
                      const SizedBox(height: 14),
                    ],
                    if (notGoing.isNotEmpty) ...[
                      const _Label('Not going'),
                      for (final invite in notGoing)
                        _NotGoingCard(
                          invite: invite,
                          busy: _answering.containsKey(invite.id),
                          onAttend: () => unawaited(_answer(invite, true)),
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
    required this.answering,
    required this.onAnswer,
    this.fit,
  });

  final EventInvite invite;

  /// The answer being sent (true = accept), or null when idle; its button
  /// shows the spinner.
  final bool? answering;
  final ValueChanged<bool> onAnswer;

  /// How it fits your day; nothing shows until (or unless) it loads.
  final Future<InviteFit?>? fit;

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
          FutureBuilder<InviteFit?>(
            future: fit,
            builder: (context, snapshot) {
              final value = snapshot.data;
              if (value == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 12),
                child: _FitView(invite: invite, fit: value),
              );
            },
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: answering != null ? null : () => onAnswer(false),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                    backgroundColor: colors.cardMuted,
                    foregroundColor: colors.textPrimary,
                    shape: buttonShape,
                  ),
                  child: answering == false
                      ? const CupertinoActivityIndicator()
                      : const Text('Decline'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: answering != null ? null : () => onAnswer(true),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                    backgroundColor: _purple,
                    foregroundColor: Colors.white,
                    shape: buttonShape,
                  ),
                  child: answering == true
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
          const SizedBox(height: 4),
          for (final uid in invite.recipientUids)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  CirclePersonAvatar(
                    name: invite.recipientNames[uid] ?? 'A friend',
                    uid: uid,
                    size: 26,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      invite.recipientNames[uid] ?? 'A friend',
                      style: TextStyle(color: colors.textPrimary, fontSize: 14),
                    ),
                  ),
                  Text(
                    switch (invite.responses[uid]) {
                      'accepted' => 'Going',
                      'declined' => "Can't make it",
                      _ => 'Waiting',
                    },
                    style: TextStyle(
                      color: invite.responses[uid] == 'accepted'
                          ? colors.success
                          : colors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// An invite you've said yes to, with a way to back out before it starts.
class _GoingCard extends StatelessWidget {
  const _GoingCard({
    required this.invite,
    required this.busy,
    required this.onBackOut,
  });

  final EventInvite invite;
  final bool busy;
  final VoidCallback onBackOut;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    // The time gets the card's full width; the button shares the last line.
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
          Row(
            children: [
              Expanded(
                child: Text(
                  'From ${invite.fromName}',
                  style: TextStyle(color: colors.textSecondary, fontSize: 13),
                ),
              ),
              TextButton(
                onPressed: busy ? null : onBackOut,
                style: TextButton.styleFrom(
                  minimumSize: const Size(44, 44),
                  foregroundColor: colors.danger,
                ),
                child: busy
                    ? const CupertinoActivityIndicator()
                    : const Text("Can't make it"),
              ),
            ],
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

/// Option B from the mock: your events on the top lane, the invite below,
/// clashes shaded across both, then a line on how it fits.
class _FitView extends StatelessWidget {
  const _FitView({required this.invite, required this.fit});

  final EventInvite invite;
  final InviteFit fit;

  static const _amber = Color(0xFFFFB340);

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final span = fit.windowEnd.difference(fit.windowStart).inMinutes;
    double at(DateTime t) =>
        (t.difference(fit.windowStart).inMinutes / span).clamp(0.0, 1.0);
    final labels = [
      for (
        var t = fit.windowStart;
        t.isBefore(fit.windowEnd);
        t = t.add(const Duration(hours: 2))
      )
        t,
    ];
    final tint = fit.warning ? _amber : colors.success;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.cardMuted,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                invite.recurrence == null
                    ? 'Your ${DateFormat('EEEE').format(fit.start)}'
                    : 'Your ${DateFormat('EEEE, MMM d').format(fit.start)}',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  Widget block(
                    FitBlock b, {
                    required double top,
                    required Color color,
                    Color? border,
                    bool bold = false,
                  }) {
                    final left = at(b.start) * width;
                    return Positioned(
                      left: left,
                      width: (at(b.end) * width - left).clamp(4.0, width),
                      top: top,
                      height: 28,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        alignment: Alignment.centerLeft,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(6),
                          border: border == null
                              ? null
                              : Border.all(color: border, width: 1.5),
                        ),
                        child: Text(
                          b.title,
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          softWrap: false,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 11,
                            fontWeight: bold
                                ? FontWeight.w700
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                    );
                  }

                  return SizedBox(
                    height: 64,
                    child: Stack(
                      children: [
                        for (final clash in fit.clashes)
                          Positioned(
                            left: at(clash.start) * width,
                            width: (at(clash.end) - at(clash.start)) * width,
                            top: 0,
                            bottom: 0,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: _amber.withValues(alpha: .18),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        for (final event in fit.events)
                          block(
                            event,
                            top: 0,
                            color: colors.textPrimary.withValues(alpha: .12),
                          ),
                        block(
                          (title: invite.title, start: fit.start, end: fit.end),
                          top: 36,
                          color: _purple.withValues(alpha: .25),
                          border: _purple,
                          bold: true,
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 6),
              LayoutBuilder(
                builder: (context, constraints) => SizedBox(
                  height: 14,
                  child: Stack(
                    children: [
                      for (final t in labels)
                        Positioned(
                          left: at(t) * constraints.maxWidth,
                          child: Text(
                            DateFormat('j').format(t),
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 10,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: tint.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                fit.warning
                    ? CupertinoIcons.exclamationmark_circle
                    : CupertinoIcons.checkmark_alt,
                size: 16,
                color: tint,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  fit.message,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// An invite you declined that hasn't happened yet: you can still go.
class _NotGoingCard extends StatelessWidget {
  const _NotGoingCard({
    required this.invite,
    required this.busy,
    required this.onAttend,
  });

  final EventInvite invite;
  final bool busy;
  final VoidCallback onAttend;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
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
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'From ${invite.fromName}',
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: colors.cardMuted,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  'You declined',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: busy ? null : onAttend,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
              foregroundColor: _purple,
              side: const BorderSide(color: _purple, width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: busy
                ? const CupertinoActivityIndicator()
                : const Text(
                    'I can attend after all',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
          ),
          const SizedBox(height: 6),
          Text(
            'Adds it to your calendar and lets ${invite.fromName} know',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
