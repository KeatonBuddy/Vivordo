import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:vivordo_health/src/utils/energy_forecast.dart';
import 'package:vivordo_health/src/utils/invite_fit.dart';

DateTime _at(int hour, [int minute = 0]) =>
    DateTime(2026, 11, 11, hour, minute);
String _t(DateTime t) => DateFormat.jm().format(t);
FitBlock _event(String title, DateTime start, DateTime end) =>
    (title: title, start: start, end: end);

void main() {
  test('a clash names the event and the overlapping time', () {
    final fit = inviteFit(
      start: _at(14),
      end: _at(16),
      dayEvents: [
        _event('Lecture', _at(12), _at(13, 30)),
        _event('Lab', _at(15), _at(16, 30)),
      ],
      dip: EnergyWindow(EnergyPhase.dip, _at(13, 30), _at(15, 30)),
    );
    expect(fit.warning, isTrue);
    expect(fit.clashes.single.start, _at(15));
    expect(fit.clashes.single.end, _at(16));
    expect(
      fit.message,
      'Clashes with Lab from ${_t(_at(15))} to ${_t(_at(16))}. '
      'It also lands in your usual afternoon dip.',
    );
    // A 7-hour strip from two hours before the invite's hour.
    expect(fit.windowStart, _at(12));
    expect(fit.windowEnd, _at(19));
    expect(fit.events.map((e) => e.title), ['Lecture', 'Lab']);
  });

  test('a free slot says how long you are free around it', () {
    final fit = inviteFit(
      start: _at(18),
      end: _at(19),
      dayEvents: [
        _event('Team sync', _at(16, 30), _at(17, 30)),
        _event('Dinner', _at(20), _at(21)),
      ],
    );
    expect(fit.warning, isFalse);
    expect(
      fit.message,
      "Fits well. You're free from ${_t(_at(17, 30))} to ${_t(_at(20))}.",
    );
  });

  test('free but in your dip is a softer warning', () {
    final fit = inviteFit(
      start: _at(14),
      end: _at(15),
      dayEvents: const [],
      dip: EnergyWindow(EnergyPhase.dip, _at(13, 30), _at(15, 30)),
    );
    expect(fit.warning, isTrue);
    expect(
      fit.message,
      'Nothing else is on your calendar that day. '
      'It lands in your usual afternoon dip, though.',
    );
  });

  test('long invites widen the strip to keep two hours either side', () {
    final fit = inviteFit(start: _at(9), end: _at(15), dayEvents: const []);
    expect(fit.windowStart, _at(7));
    expect(fit.windowEnd, _at(17));
  });
}
