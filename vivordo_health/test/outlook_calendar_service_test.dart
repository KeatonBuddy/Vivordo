import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/services/outlook_calendar_service.dart';

void main() {
  test(
    'benched Outlook calendar performs no authentication or event load',
    () async {
      expect(OutlookCalendarService.enabled, isFalse);

      final events = await OutlookCalendarService.getEventsBetween(
        DateTime(2026, 9, 1),
        DateTime(2026, 9, 2),
      );

      expect(events, isEmpty);
      expect(await OutlookCalendarService.isSignedIn(), isFalse);
    },
  );
}
