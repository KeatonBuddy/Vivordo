import 'dart:async';

import 'keyed_entry_cache.dart';

/// Collapses repeated reads of the same remote resource.
///
/// Two things happen here. Callers asking for the same key while a request is
/// already in flight join that request instead of starting another, and a
/// completed result is reused for [ttl] afterwards.
///
/// Failures are never cached: an error propagates to everyone waiting on that
/// request and the next caller retries. A short [ttl] keeps a transient empty
/// result — the shape several callers return when auth briefly drops — from
/// sticking around.
class RequestCoalescer<T> {
  RequestCoalescer({required Duration ttl})
    : _cache = KeyedEntryCache<T>(ttl: ttl);

  final KeyedEntryCache<T> _cache;
  final Map<String, Future<T>> _inFlight = {};

  /// Per-key token bumped by every new fetch and every invalidation. A request
  /// only writes its result if its token is still current, so a slow request
  /// cannot overwrite a newer one or resurrect data invalidated while it was
  /// in flight.
  final Map<String, int> _generations = {};

  /// Number of times [fetch] actually ran. Test-only signal.
  int get fetchCount => _fetchCount;
  int _fetchCount = 0;

  /// Returns the value for [key], fetching only when necessary.
  ///
  /// [forceRefresh] skips both the cached value and any in-flight request, so
  /// a pull-to-refresh always reaches the network and its result becomes the
  /// new cached value.
  Future<T> run(
    String key,
    Future<T> Function() fetch, {
    bool forceRefresh = false,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();

    if (!forceRefresh) {
      final cached = _cache.read(key, at);
      if (cached != null) return Future.value(cached);

      final pending = _inFlight[key];
      if (pending != null) return pending;
    }

    _fetchCount++;
    final generation = _bumpGeneration(key);
    late final Future<T> request;
    request = fetch()
        .then((value) {
          // Discard the result if a refresh or an invalidation happened while
          // this request was in flight — that newer intent wins.
          if (_generations[key] == generation) {
            _cache.write(key, value, now ?? DateTime.now());
          }
          return value;
        })
        .whenComplete(() {
          // Only clear the slot if it still belongs to this request; a forced
          // refresh may have replaced it in the meantime.
          if (identical(_inFlight[key], request)) _inFlight.remove(key);
        });

    _inFlight[key] = request;
    return request;
  }

  /// Drops [key] so the next read goes back to the source. Call after an edit
  /// or deletion that changes what the key would return.
  ///
  /// Any request already in flight for [key] is disowned: its callers still
  /// receive its result, but it will not be written to the cache.
  void invalidate(String key) {
    _bumpGeneration(key);
    _cache.invalidate(key);
    _inFlight.remove(key);
  }

  /// Drops every key outside [keys], disowning their in-flight requests.
  /// Used when the set of things worth tracking shrinks.
  void retainOnly(Iterable<String> keys) {
    final keep = keys.toSet();
    for (final key in _generations.keys.toList()) {
      if (!keep.contains(key)) _bumpGeneration(key);
    }
    _cache.retainOnly(keep);
    _inFlight.removeWhere((key, _) => !keep.contains(key));
  }

  /// Drops everything. Call when the signed-in account changes, since every
  /// key belonged to the previous account.
  void invalidateAll() {
    for (final key in _generations.keys.toList()) {
      _bumpGeneration(key);
    }
    _cache.clear();
    _inFlight.clear();
  }

  int _bumpGeneration(String key) {
    final next = (_generations[key] ?? 0) + 1;
    _generations[key] = next;
    return next;
  }
}
