/// A small time-bounded cache keyed by id, used to share fetched records
/// between callers that would otherwise each issue their own read.
///
/// Entries expire after [ttl] so a record edited elsewhere is picked up
/// without the viewer restarting the app, and callers can evict explicitly
/// the moment they know a record changed.
class KeyedEntryCache<T> {
  KeyedEntryCache({required this.ttl});

  final Duration ttl;
  final Map<String, _CacheEntry<T>> _entries = {};

  /// The cached value for [key], or null when absent or older than [ttl].
  T? read(String key, DateTime now) {
    final entry = _entries[key];
    if (entry == null) return null;
    if (now.difference(entry.storedAt) >= ttl) {
      _entries.remove(key);
      return null;
    }
    return entry.value;
  }

  void write(String key, T value, DateTime now) {
    _entries[key] = _CacheEntry(value: value, storedAt: now);
  }

  /// Drops [key], so the next read re-fetches it.
  void invalidate(String key) => _entries.remove(key);

  /// Drops everything outside [keys] — the caller no longer tracks those
  /// records, so holding them would leak and could serve a stale value if the
  /// same id came back later.
  void retainOnly(Iterable<String> keys) {
    final keep = keys.toSet();
    _entries.removeWhere((key, _) => !keep.contains(key));
  }

  void clear() => _entries.clear();

  /// Ids currently held, regardless of freshness. Test-only signal.
  Iterable<String> get keys => _entries.keys;
}

class _CacheEntry<T> {
  const _CacheEntry({required this.value, required this.storedAt});

  final T value;
  final DateTime storedAt;
}
