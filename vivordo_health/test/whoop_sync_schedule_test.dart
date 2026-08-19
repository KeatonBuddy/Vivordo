import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/whoop_sync_schedule.dart';

void main() {
  test('suppresses automatic WHOOP syncs before 4 a.m.', () {
    final time = DateTime(2026, 8, 19, 3, 59);

    expect(whoopAutomaticSyncSlot(time), WhoopAutomaticSyncSlot.overnight);
    expect(whoopAutomaticSyncSlotKey('user-1', time), isNull);
  });

  test('creates one stable morning slot key', () {
    expect(
      whoopAutomaticSyncSlotKey('user-1', DateTime(2026, 8, 19, 4)),
      'user-1:2026-08-19:morning',
    );
    expect(
      whoopAutomaticSyncSlotKey('user-1', DateTime(2026, 8, 19, 11, 59)),
      'user-1:2026-08-19:morning',
    );
  });

  test('changes to the midday slot at noon', () {
    expect(
      whoopAutomaticSyncSlotKey('user-1', DateTime(2026, 8, 19, 12)),
      'user-1:2026-08-19:midday',
    );
  });

  test('slot keys are isolated by user and date', () {
    final first = whoopAutomaticSyncSlotKey('user-1', DateTime(2026, 8, 19, 9));
    final second = whoopAutomaticSyncSlotKey(
      'user-2',
      DateTime(2026, 8, 20, 9),
    );

    expect(first, isNot(second));
  });
}
