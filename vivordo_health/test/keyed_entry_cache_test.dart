import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/keyed_entry_cache.dart';

void main() {
  final start = DateTime(2026, 9, 18, 9);

  KeyedEntryCache<String> cache() =>
      KeyedEntryCache<String>(ttl: const Duration(minutes: 2));

  test('serves a stored value inside the window', () {
    final subject = cache()..write('amy', 'Amy', start);
    expect(
      subject.read('amy', start.add(const Duration(seconds: 119))),
      'Amy',
    );
  });

  test('stops serving once the entry reaches the ttl', () {
    final subject = cache()..write('amy', 'Amy', start);
    expect(subject.read('amy', start.add(const Duration(minutes: 2))), isNull);
  });

  test('drops the expired entry rather than holding it', () {
    final subject = cache()..write('amy', 'Amy', start);
    subject.read('amy', start.add(const Duration(minutes: 5)));
    expect(subject.keys, isEmpty);
  });

  test('returns null for an id it never held', () {
    expect(cache().read('nobody', start), isNull);
  });

  test('invalidate forces the next read to miss', () {
    final subject = cache()..write('amy', 'Amy', start);
    subject.invalidate('amy');
    expect(subject.read('amy', start), isNull);
  });

  test('a later write extends the window', () {
    final subject = cache()..write('amy', 'Amy', start);
    subject.write('amy', 'Amy Renamed', start.add(const Duration(minutes: 1)));
    expect(
      subject.read('amy', start.add(const Duration(minutes: 2, seconds: 30))),
      'Amy Renamed',
    );
  });

  group('retainOnly', () {
    test('evicts ids no longer in the list, as after a removal or block', () {
      final subject = cache()
        ..write('amy', 'Amy', start)
        ..write('ben', 'Ben', start)
        ..write('cal', 'Cal', start);

      subject.retainOnly(['amy', 'cal']);

      expect(subject.read('ben', start), isNull);
      expect(subject.read('amy', start), 'Amy');
      expect(subject.read('cal', start), 'Cal');
    });

    test('an empty list clears everything', () {
      final subject = cache()..write('amy', 'Amy', start);
      subject.retainOnly(const []);
      expect(subject.keys, isEmpty);
    });

    test('keeps entries when the list is unchanged', () {
      final subject = cache()..write('amy', 'Amy', start);
      subject.retainOnly(['amy']);
      expect(subject.read('amy', start), 'Amy');
    });
  });

  test('clear empties the cache, as on sign-out', () {
    final subject = cache()
      ..write('amy', 'Amy', start)
      ..write('ben', 'Ben', start);
    subject.clear();
    expect(subject.keys, isEmpty);
    expect(subject.read('amy', start), isNull);
  });
}
