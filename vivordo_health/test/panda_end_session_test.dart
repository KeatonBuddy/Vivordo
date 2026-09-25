import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/services/panda_prompts.dart';

void main() {
  test('end-session suggestion is opt-in and must be a boolean', () {
    for (final value in [null, false, 'true', true]) {
      final reply = PandaPrompts.parseTurnReply(
        jsonEncode({
          'intent': 'chitchat',
          'message': 'You have a plan for today.',
          if (value != null) 'offer_end_session': value,
        }),
      );
      expect(reply.offerEndSession, value == true);
    }
  });
}
