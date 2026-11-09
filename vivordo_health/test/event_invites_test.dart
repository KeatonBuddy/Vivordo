import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/screens/invites_screen.dart';
import 'package:vivordo_health/src/services/circle_profile_service.dart';
import 'package:vivordo_health/src/services/event_invite_service.dart';
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

    await tester.tap(find.text('maya.k'));
    await tester.pump();
    expect(selected, ['m']);
    expect(find.text('1 selected'), findsOneWidget);

    await tester.tap(find.text('jordan.t'));
    await tester.pump();
    await tester.tap(find.text('maya.k'));
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

    expect(
      find.text('maya.k invited you', findRichText: true),
      findsOneWidget,
    );
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
}
