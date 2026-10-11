import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/request_coalescer.dart';

void main() {
  final start = DateTime(2026, 9, 18, 9);

  RequestCoalescer<String> coalescer() =>
      RequestCoalescer<String>(ttl: const Duration(seconds: 30));

  test('concurrent callers for one key share a single fetch', () async {
    final subject = coalescer();
    final gate = Completer<String>();

    final first = subject.run('week', () => gate.future, now: start);
    final second = subject.run('week', () => gate.future, now: start);
    final third = subject.run('week', () => gate.future, now: start);

    gate.complete('events');

    expect(await Future.wait([first, second, third]), [
      'events',
      'events',
      'events',
    ]);
    expect(subject.fetchCount, 1);
  });

  test('different keys are fetched independently', () async {
    final subject = coalescer();
    await subject.run('week-a', () async => 'a', now: start);
    await subject.run('week-b', () async => 'b', now: start);
    expect(subject.fetchCount, 2);
  });

  test('a later caller inside the window reuses the result', () async {
    final subject = coalescer();
    await subject.run('week', () async => 'events', now: start);

    final again = await subject.run(
      'week',
      () async => 'should not run',
      now: start.add(const Duration(seconds: 29)),
    );

    expect(again, 'events');
    expect(subject.fetchCount, 1);
  });

  test('the window expires and the next caller refetches', () async {
    final subject = coalescer();
    await subject.run('week', () async => 'stale', now: start);

    final again = await subject.run(
      'week',
      () async => 'fresh',
      now: start.add(const Duration(seconds: 30)),
    );

    expect(again, 'fresh');
    expect(subject.fetchCount, 2);
  });

  group('forceRefresh', () {
    test('ignores a cached value and replaces it', () async {
      final subject = coalescer();
      await subject.run('week', () async => 'stale', now: start);

      final refreshed = await subject.run(
        'week',
        () async => 'fresh',
        forceRefresh: true,
        now: start,
      );
      expect(refreshed, 'fresh');
      expect(subject.fetchCount, 2);

      // The forced result is what later callers now see.
      final subsequent = await subject.run(
        'week',
        () async => 'should not run',
        now: start,
      );
      expect(subsequent, 'fresh');
      expect(subject.fetchCount, 2);
    });

    test('does not join an in-flight request', () async {
      final subject = coalescer();
      final gate = Completer<String>();

      final pending = subject.run('week', () => gate.future, now: start);
      final forced = subject.run(
        'week',
        () async => 'fresh',
        forceRefresh: true,
        now: start,
      );

      expect(await forced, 'fresh');
      gate.complete('stale');
      await pending;
      expect(subject.fetchCount, 2);
    });

    test('an older request finishing later does not overwrite it', () async {
      final subject = coalescer();
      final slow = Completer<String>();

      // The original request is still outstanding when the refresh lands.
      final pending = subject.run('week', () => slow.future, now: start);
      await subject.run(
        'week',
        () async => 'fresh',
        forceRefresh: true,
        now: start,
      );

      // Now the stale one completes, after the fresh result was cached.
      slow.complete('stale');
      expect(await pending, 'stale');

      final served = await subject.run(
        'week',
        () async => 'should not run',
        now: start,
      );
      expect(served, 'fresh');
      expect(subject.fetchCount, 2);
    });
  });

  group('invalidation', () {
    test('invalidate sends the next caller back to the source', () async {
      final subject = coalescer();
      await subject.run('week', () async => 'before edit', now: start);

      subject.invalidate('week');

      final after = await subject.run(
        'week',
        () async => 'after edit',
        now: start,
      );
      expect(after, 'after edit');
      expect(subject.fetchCount, 2);
    });

    test('invalidateAll clears every key, as on an account change', () async {
      final subject = coalescer();
      await subject.run('week-a', () async => 'a', now: start);
      await subject.run('week-b', () async => 'b', now: start);

      subject.invalidateAll();

      await subject.run('week-a', () async => 'a2', now: start);
      await subject.run('week-b', () async => 'b2', now: start);
      expect(subject.fetchCount, 4);
    });

    test('a request in flight when invalidate lands is not cached', () async {
      final subject = coalescer();
      final gate = Completer<String>();

      // Mirrors deleting an event while its range is already being fetched.
      final pending = subject.run('week', () => gate.future, now: start);
      subject.invalidate('week');
      gate.complete('includes the deleted event');
      expect(await pending, 'includes the deleted event');

      // The deleted event must not come back from the cache.
      final after = await subject.run(
        'week',
        () async => 'without the deleted event',
        now: start,
      );
      expect(after, 'without the deleted event');
      expect(subject.fetchCount, 2);
    });

    test('retainOnly drops keys outside the set', () async {
      final subject = coalescer();
      await subject.run('amy', () async => 'Amy', now: start);
      await subject.run('ben', () async => 'Ben', now: start);

      subject.retainOnly(['amy']);

      expect(await subject.run('amy', () async => 'refetched', now: start), 'Amy');
      expect(await subject.run('ben', () async => 'refetched', now: start),
          'refetched');
      expect(subject.fetchCount, 3);
    });

    test('a request in flight when retainOnly drops its key is not cached',
        () async {
      final subject = coalescer();
      final gate = Completer<String>();

      // Mirrors a friend being removed while their profile is still loading.
      final pending = subject.run('ben', () => gate.future, now: start);
      subject.retainOnly(['amy']);
      gate.complete('Ben');
      await pending;

      final after = await subject.run('ben', () async => 'refetched', now: start);
      expect(after, 'refetched');
      expect(subject.fetchCount, 2);
    });

    test('a request in flight when invalidateAll lands is not cached', () async {
      final subject = coalescer();
      final gate = Completer<String>();

      final pending = subject.run('week', () => gate.future, now: start);
      subject.invalidateAll();
      gate.complete('previous account');
      await pending;

      final after = await subject.run(
        'week',
        () async => 'new account',
        now: start,
      );
      expect(after, 'new account');
      expect(subject.fetchCount, 2);
    });
  });

  group('failures', () {
    test('are not cached, so the next caller retries', () async {
      final subject = coalescer();

      await expectLater(
        subject.run('week', () async => throw StateError('offline'), now: start),
        throwsStateError,
      );

      final recovered = await subject.run(
        'week',
        () async => 'events',
        now: start,
      );
      expect(recovered, 'events');
      expect(subject.fetchCount, 2);
    });

    test('propagate to everyone sharing the request', () async {
      final subject = coalescer();
      final gate = Completer<String>();

      final first = subject.run('week', () => gate.future, now: start);
      final second = subject.run('week', () => gate.future, now: start);

      gate.completeError(StateError('offline'));

      await expectLater(first, throwsStateError);
      await expectLater(second, throwsStateError);
      expect(subject.fetchCount, 1);
    });
  });
}
