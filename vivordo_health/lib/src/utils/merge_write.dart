import 'package:cloud_firestore/cloud_firestore.dart';

/// Fields every sync write stamps afresh; they don't make a write a change.
const _writeTimestamps = {'syncedAt', 'updatedAt'};

/// Whether `set(data, SetOptions(merge: true))` onto a document holding
/// [existing] (null when it doesn't exist) would change anything but its
/// write timestamps.
///
/// A Health sync rewrites every day it reads, and nearly all of them come
/// back with the values they already hold, yet each write makes every live
/// metrics_daily window re-send all its days. Merge semantics: nested maps
/// merge, so only the fields in [data] are compared; lists and other values
/// replace, so they must match exactly. A [FieldValue] other than under a
/// timestamp field (here only ever `FieldValue.delete()`) is unchanged when
/// the field is already absent. Anything else counts as a change, so an
/// unexpected value errs toward writing.
bool mergeWouldChange(
  Map<String, dynamic>? existing,
  Map<String, dynamic> data,
) => !_mergeKeeps(existing ?? const {}, data);

bool _mergeKeeps(Map existing, Map data) {
  for (final MapEntry(:key, :value) in data.entries) {
    if (_writeTimestamps.contains(key)) continue;
    if (value is FieldValue) {
      if (existing.containsKey(key)) return false;
    } else if (value is Map) {
      final current = existing[key];
      if (!_mergeKeeps(current is Map ? current : const {}, value)) {
        return false;
      }
    } else if (!_same(existing[key], value)) {
      return false;
    }
  }
  return true;
}

bool _same(Object? a, Object? b) {
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_same(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final MapEntry(:key, :value) in b.entries) {
      if (!a.containsKey(key) || !_same(a[key], value)) return false;
    }
    return true;
  }
  return a == b;
}
