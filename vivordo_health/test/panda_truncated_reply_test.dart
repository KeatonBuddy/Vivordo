import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/services/panda_prompts.dart';

void main() {
  test('truncated reply keeps the message text instead of "Got it"', () {
    final reply = PandaPrompts.parseTurnReply(
      '{"intent":"chitchat","message":"Start with the Q3 report.\\nThen take a short \\"reset\\" break after Client prep, around 9',
    );
    expect(reply.message, startsWith('Incomplete response'));
    expect(
      reply.message,
      contains(
        'Start with the Q3 report.\nThen take a short "reset" break after Client prep, around 9',
      ),
    );
  });

  test('reply cut inside a unicode escape still recovers the text', () {
    final reply = PandaPrompts.parseTurnReply(
      '{"intent":"chitchat","message":"Plan the day \\u2014 then \\u20',
    );
    expect(reply.message, startsWith('Incomplete response'));
    expect(reply.message, endsWith('Plan the day — then'));
  });

  test('reply with no message explicitly reports interruption', () {
    expect(
      PandaPrompts.parseTurnReply('{"intent":"chit').message,
      contains('No changes were made'),
    );
  });
  test(
    'incomplete actions never display success or carry executable payloads',
    () {
      for (final intent in ['calendar_action', 'priority_action']) {
        final reply = PandaPrompts.parseTurnReply(
          '{"intent":"$intent","message":"Done, I deleted it.","$intent":{',
        );
        expect(reply.intent, PandaIntent.chitchat);
        expect(reply.message, contains('No changes were made'));
        expect(reply.message, isNot(contains('I deleted it')));
        expect(reply.calendarAction, isNull);
        expect(reply.priorityAction, isNull);
      }
    },
  );
}
