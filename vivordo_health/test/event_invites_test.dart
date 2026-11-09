import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:vivordo_health/screens/invites_screen.dart';
import 'package:vivordo_health/src/services/circle_profile_service.dart';
import 'package:vivordo_health/src/services/event_invite_service.dart';
import 'package:vivordo_health/src/utils/invite_fit.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';
import 'package:vivordo_health/widgets/add_calendar_event_sheet.dart';

final _soon = DateTime.now().add(const Duration(days: 2));

EventInvite _invite({
  String id = 'i1',
  Map<String, String> responses = const {'me': 'pending'},
  bool cancelled = false,
  DateTime? start,
}) {
  final from = start ?? DateTime(_soon.year, _soon.month, _soon.day, 18, 30);
  return EventInvite(
    id: id,
    fromUid: 'maya',
    fromName: 'maya.k',
    title: 'Run club',
    start: from,
    end: from.add(const Duration(hours: 1)),
    recipientUids: responses.keys.toList(),
    responses: responses,
    cancelled: cancelled,
  );
}

Widget _app(Widget child) => MaterialApp(
  theme: VivordoTheme.light,
  home: Scaffold(body: child),
);

void main() {
  test('only live invites still waiting on you count as pending', () {
    final now = DateTime.now();
    expect(_invite().pendingFor('me', now), isTrue);
    expect(
      _invite(responses: {'me': 'accepted'}).pendingFor('me', now),
      isFalse,
    );
    expect(_invite(cancelled: true).pendingFor('me', now), isFalse);
    expect(
      _invite(
        start: now.subtract(const Duration(hours: 3)),
      ).pendingFor('me', now),
      isFalse,
    );
    expect(_invite().pendingFor('someone else', now), isFalse);
  });

  test('replies leave out answers nobody gave', () {
    final invite = _invite(
      responses: {'a': 'accepted', 'b': 'accepted', 'c': 'declined'},
    );
    expect(inviteReplies(invite), "2 going · 1 can't make it");
  });

  testWidgets('choosing friends reports their uids', (tester) async {
    var selected = <String>[];
    final friends = Stream.value([
      const CircleProfile(
        uid: 'j',
        username: 'jordan.t',
        friendCode: '',
        bio: '',
      ),
      const CircleProfile(
        uid: 'm',
        username: 'maya.k',
        friendCode: '',
        bio: '',
      ),
    ]);
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) => InviteFriendsSection(
            selected: selected,
            friends: friends,
            onChanged: (uids) => setState(() => selected = uids),
          ),
        ),
      ),
    );
    await tester.pump();
    // Nobody is listed until you search.
    expect(find.text('maya.k'), findsNothing);

    await tester.enterText(find.byType(TextField), 'MAY');
    await tester.pump();
    expect(find.text('jordan.t'), findsNothing);
    await tester.tap(find.text('maya.k'));
    await tester.pump();
    expect(selected, ['m']);
    expect(find.text('1 selected'), findsOneWidget);
    // Picking clears the search; the friend stays as a chip.
    expect(find.text('maya.k'), findsOneWidget);
    expect(find.bySemanticsLabel('Remove maya.k'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'zz');
    await tester.pump();
    expect(find.text('No friends match “zz”.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'j');
    await tester.pump();
    await tester.tap(find.text('jordan.t'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Remove maya.k'));
    await tester.pump();
    expect(selected, ['j']);
  });

  testWidgets('no friends, no invite section', (tester) async {
    await tester.pumpWidget(
      _app(
        InviteFriendsSection(
          selected: const [],
          friends: Stream.value(const []),
          onChanged: (_) {},
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Invite friends'), findsNothing);
  });

  testWidgets('accepting an invite answers it as going', (tester) async {
    // Waiting, Not going and You sent all on one screen.
    tester.view.physicalSize = const Size(430, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final answers = <(String, bool)>[];
    final received = StreamController<List<EventInvite>>();
    await tester.pumpWidget(
      _app(
        InvitesScreen(
          uid: 'me',
          received: received.stream,
          sent: Stream.value([
            _invite(id: 's1', responses: {'a': 'accepted', 'b': 'pending'}),
          ]),
          respond: (invite, {required accept}) async =>
              answers.add((invite.id, accept)),
        ),
      ),
    );
    received.add([
      _invite(),
      _invite(id: 'old', responses: {'me': 'declined'}),
    ]);
    await tester.pump();

    expect(find.text('maya.k invited you', findRichText: true), findsOneWidget);
    expect(find.text('Waiting for you'), findsOneWidget);
    expect(find.text('1 going · 1 waiting'), findsOneWidget);

    await tester.tap(find.text('Accept'));
    await tester.pump();
    expect(answers, [('i1', true)]);
    await received.close();
  });

  testWidgets('with nothing to show, Invites explains how they work', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        InvitesScreen(
          uid: 'me',
          received: Stream.value(const []),
          sent: Stream.value(const []),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('No invites yet'), findsOneWidget);
  });

  testWidgets('the envelope shows how many invites wait', (tester) async {
    await tester.pumpWidget(_app(InvitesButton(pendingCount: Stream.value(2))));
    await tester.pump();
    expect(find.text('2'), findsOneWidget);
    expect(find.byTooltip('Invites, 2 waiting'), findsOneWidget);

    await tester.pumpWidget(
      _app(InvitesButton(key: UniqueKey(), pendingCount: Stream.value(0))),
    );
    await tester.pump();
    expect(find.text('0'), findsNothing);
    expect(find.byTooltip('Invites'), findsOneWidget);
  });

  testWidgets('an accepted invite can be backed out of after confirming', (
    tester,
  ) async {
    final answers = <(String, bool)>[];
    await tester.pumpWidget(
      _app(
        InvitesScreen(
          uid: 'me',
          received: Stream.value([
            _invite(responses: {'me': 'accepted'}),
          ]),
          sent: Stream.value(const []),
          respond: (invite, {required accept}) async =>
              answers.add((invite.id, accept)),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Going'), findsOneWidget);
    expect(find.text('From maya.k'), findsOneWidget);

    await tester.tap(find.text("Can't make it"));
    await tester.pumpAndSettle();
    expect(answers, isEmpty, reason: 'asks first');
    await tester.tap(find.text("Can't make it").last);
    await tester.pumpAndSettle();
    expect(answers, [('i1', false)]);
  });

  testWidgets('the sender sees each friend and their answer', (tester) async {
    await tester.pumpWidget(
      _app(
        InvitesScreen(
          uid: 'maya',
          received: Stream.value(const []),
          sent: Stream.value([
            EventInvite(
              id: 's1',
              fromUid: 'maya',
              fromName: 'maya.k',
              title: 'Run club',
              start: _soon,
              end: _soon.add(const Duration(hours: 1)),
              recipientUids: const ['j', 'r', 'x'],
              recipientNames: const {'j': 'jordan.t', 'r': 'Rohan'},
              responses: const {
                'j': 'accepted',
                'r': 'declined',
                'x': 'pending',
              },
            ),
          ]),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('jordan.t'), findsOneWidget);
    expect(find.text('Rohan'), findsOneWidget);
    expect(find.text('A friend'), findsOneWidget);
    expect(find.text('Going'), findsOneWidget);
    expect(find.text("Can't make it"), findsOneWidget);
    expect(find.text('Waiting'), findsOneWidget);
  });

  testWidgets('a waiting invite shows how it fits your day', (tester) async {
    final invite = _invite();
    await tester.pumpWidget(
      _app(
        InvitesScreen(
          uid: 'me',
          received: Stream.value([invite]),
          sent: Stream.value(const []),
          loadFit: (_) async => inviteFit(
            start: invite.start,
            end: invite.end,
            dayEvents: [
              (
                title: 'Lab',
                start: invite.start.add(const Duration(minutes: 30)),
                end: invite.end.add(const Duration(hours: 1)),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Your '), findsOneWidget);
    expect(find.text('Lab'), findsOneWidget);
    expect(find.textContaining('Clashes with Lab'), findsOneWidget);
  });

  testWidgets('a declined invite can be attended after all', (tester) async {
    final answers = <(String, bool)>[];
    await tester.pumpWidget(
      _app(
        InvitesScreen(
          uid: 'me',
          received: Stream.value([
            _invite(responses: {'me': 'declined'}),
          ]),
          sent: Stream.value(const []),
          respond: (invite, {required accept}) async =>
              answers.add((invite.id, accept)),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Not going'), findsOneWidget);
    expect(find.text('You declined'), findsOneWidget);
    await tester.tap(find.text('I can attend after all'));
    await tester.pump();
    expect(answers, [('i1', true)]);
  });

  testWidgets('declining offers Undo, which puts it back to waiting', (
    tester,
  ) async {
    final undone = <String>[];
    await tester.pumpWidget(
      _app(
        InvitesScreen(
          uid: 'me',
          received: Stream.value([_invite()]),
          sent: Stream.value(const []),
          respond: (invite, {required accept}) async {},
          undoDecline: (invite) async => undone.add(invite.id),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Decline'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Declined. maya.k will be told.'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(undone, ['i1']);
  });

  test('a series reads as its rule, and stays on until it ends', () {
    final now = DateTime(2026, 11, 9, 12);
    final first = DateTime(2026, 11, 11, 18);
    final series = EventInvite(
      id: 's',
      fromUid: 'maya',
      fromName: 'maya.k',
      title: 'Run club',
      start: first,
      end: first.add(const Duration(hours: 1)),
      recurrence: 'RRULE:FREQ=WEEKLY;BYDAY=WE',
      expireAt: DateTime(2027, 5, 1),
      responses: const {'me': 'pending'},
    );
    expect(
      inviteWhen(series, now: now),
      'Every week on Wed · ${DateFormat.jm().format(first)} – '
      '${DateFormat.jm().format(first.add(const Duration(hours: 1)))}'
      ' · from\u00A0Wed,\u00A0Nov\u00A011',
    );
    // Past its first occurrence, still answerable until the series ends.
    expect(series.pendingFor('me', DateTime(2026, 12, 1)), isTrue);
    expect(series.pendingFor('me', DateTime(2027, 6, 1)), isFalse);
  });

  group('calendar copies of accepted invites', () {
    final now = DateTime.now();
    final going = _invite(responses: {'me': 'accepted'});
    Map<String, dynamic> copyOf(EventInvite invite) => {
      'eventId': 'e1',
      'title': invite.title,
      'start': Timestamp.fromDate(invite.start),
      'end': Timestamp.fromDate(invite.end),
      'allDay': invite.allDay,
    };
    CopyAction action(Map<String, dynamic> copy, EventInvite? invite) =>
        copyAction(copy: copy, invite: invite, uid: 'me', now: now);

    test('an unchanged invite leaves the copy alone', () {
      expect(action(copyOf(going), going), CopyAction.keep);
    });

    test('a moved or renamed event replaces the copy', () {
      final moved = _invite(
        responses: {'me': 'accepted'},
        start: going.start.add(const Duration(hours: 1)),
      );
      expect(action(copyOf(going), moved), CopyAction.replace);
      // Copies saved before details were kept get refreshed once.
      expect(action({'eventId': 'e1'}, going), CopyAction.replace);
    });

    test('cancelled, declined or gone before it happens: removed', () {
      final copy = copyOf(going);
      expect(
        action(copy, _invite(responses: {'me': 'accepted'}, cancelled: true)),
        CopyAction.remove,
      );
      expect(
        action(copy, _invite(responses: {'me': 'declined'})),
        CopyAction.remove,
      );
      expect(action(copy, null), CopyAction.remove);
    });

    test('after the event, copies stay in the calendar but stop syncing', () {
      final past = _invite(
        responses: {'me': 'accepted'},
        start: now.subtract(const Duration(hours: 3)),
      );
      expect(action(copyOf(past), past), CopyAction.forget);
      expect(action(copyOf(past), null), CopyAction.forget);
      expect(action({'eventId': 'e1'}, null), CopyAction.forget);
    });

    test('single changes from the sender change just those occurrences', () {
      final changed = EventInvite.fromMap('i1', {
        'fromUid': 'maya',
        'title': going.title,
        'start': Timestamp.fromDate(going.start),
        'end': Timestamp.fromDate(going.end),
        'recurrence': 'RRULE:FREQ=WEEKLY',
        'expireAt': Timestamp.fromDate(
          going.start.add(const Duration(days: 90)),
        ),
        'responses': {'me': 'accepted'},
        'exceptions': {
          '${going.start.add(const Duration(days: 7)).millisecondsSinceEpoch}':
              {'cancelled': true},
        },
      });
      final copy = {...copyOf(going), 'recurrence': 'RRULE:FREQ=WEEKLY'};
      expect(action(copy, changed), CopyAction.occurrences);
      // Once applied, the copy records them and stays put.
      expect(
        action({...copy, 'exceptions': changed.exceptionsData}, changed),
        CopyAction.keep,
      );
    });
  });

  group('single changes to a series', () {
    final first = DateTime(2026, 11, 10, 18);
    final week = const Duration(days: 7);
    final series = EventInvite.fromMap('s', {
      'fromUid': 'maya',
      'title': 'Weekly run',
      'start': Timestamp.fromDate(first),
      'end': Timestamp.fromDate(first.add(const Duration(hours: 1))),
      'recurrence': 'RRULE:FREQ=WEEKLY',
      'expireAt': Timestamp.fromDate(DateTime(2027, 5, 1)),
      'exceptions': {
        '${first.add(week).millisecondsSinceEpoch}': {'cancelled': true},
        '${first.add(week * 2).millisecondsSinceEpoch}': {
          'title': 'Weekly run',
          'start': first
              .add(week * 2 + const Duration(minutes: 30))
              .millisecondsSinceEpoch,
          'end': first
              .add(week * 2 + const Duration(minutes: 90))
              .millisecondsSinceEpoch,
        },
        'junk': {'cancelled': true},
      },
    });

    test('are keyed by where each occurrence began', () {
      expect(series.exceptions.keys, [first.add(week), first.add(week * 2)]);
      expect(series.exceptions[first.add(week)]!.cancelled, isTrue);
    });

    test('the next occurrences skip cancelled ones and use moved times', () {
      final next = series.nextOccurrences(first);
      expect(next.map((o) => o.start), [
        first,
        first.add(week * 2 + const Duration(minutes: 30)),
        first.add(week * 3),
      ]);
      expect(next[1].end, first.add(week * 2 + const Duration(minutes: 90)));
    });

    test('show under the time while still ahead', () {
      final moved = first.add(week * 2 + const Duration(minutes: 30));
      expect(
        inviteChanges(series, now: first),
        'Nov 17 cancelled · Nov 24 moved to ${DateFormat.jm().format(moved)}'
            .split(' · ')
            .map((p) => p.replaceAll(' ', '\u00A0'))
            .join(' · '),
      );
      expect(
        inviteChanges(series, now: first.add(week * 2)),
        contains('Nov\u00A024'),
      );
      expect(inviteChanges(series, now: first.add(week * 3)), isEmpty);
      expect(inviteWhen(series, now: first).split('\n'), hasLength(2));
    });
  });
}
