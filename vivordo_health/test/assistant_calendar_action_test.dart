import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/services/assistant_actions.dart';
import 'package:vivordo_health/src/services/panda_prompts.dart';

void main() {
  Map<String, Object> create([String? calendar]) => {
    'operation': 'create',
    'title': 'Run',
    'start': '2026-10-14T18:00',
    'end': '2026-10-14T18:45',
    'calendar': ?calendar,
  };

  test('a new event goes to the default calendar unless one is named', () {
    final unnamed = PandaPrompts.calendarActionFrom(create())!;
    expect(unnamed.calendar, isNull);
    expect(calendarActionSummary(unnamed), 'Create “Run”');

    final outlook = PandaPrompts.calendarActionFrom(create('outlook'))!;
    expect(outlook.calendar, 'outlook');
    expect(calendarActionSummary(outlook), 'Create “Run” in Outlook');

    // Anything else is ignored, so it lands in the default calendar.
    expect(PandaPrompts.calendarActionFrom(create('icloud'))!.calendar, isNull);
  });
}
