import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../utils/day_key.dart';

/// Copies Apple Watch VO₂ max (cardio fitness) into
/// `metrics_daily/{day}.vo2_max` for Physical Health. The health plugin
/// can't read VO₂ max, so it comes through a native channel
/// (ios/Runner/AppDelegate.swift, Vo2MaxReader).
class Vo2MaxService {
  Vo2MaxService._();

  static const _channel = MethodChannel('com.vivordo.health/vo2_max');
  static const _interval = Duration(hours: 6);
  static DateTime? _lastSync;
  static String? _lastUid;

  /// The latest reading of each local day, from samples of
  /// `{date: ms since epoch, value: ml/kg/min}`.
  static Map<String, double> latestByDay(List<Object?> samples) {
    final days = <String, ({int at, double value})>{};
    for (final sample in samples.whereType<Map>()) {
      final at = (sample['date'] as num?)?.toInt();
      final value = (sample['value'] as num?)?.toDouble();
      if (at == null || value == null || value <= 0 || value > 100) continue;
      final day = localDayKey(DateTime.fromMillisecondsSinceEpoch(at));
      final current = days[day];
      if (current == null || at >= current.at) {
        days[day] = (at: at, value: value);
      }
    }
    return {
      for (final MapEntry(:key, :value) in days.entries) key: value.value,
    };
  }

  /// Reads the last 120 days the first time each session, then the last
  /// week, at most every 6 hours. Never throws.
  static Future<void> sync() async {
    final user = FirebaseAuth.instance.currentUser;
    if (!Platform.isIOS || user == null) return;
    final now = DateTime.now();
    final first = _lastUid != user.uid;
    if (!first && _lastSync != null && now.difference(_lastSync!) < _interval) {
      return;
    }
    _lastSync = now;
    _lastUid = user.uid;
    try {
      final samples = await _channel.invokeMethod<List<Object?>>('read', {
        'days': first ? 120 : 7,
      });
      final days = latestByDay(samples ?? const []);
      if (days.isEmpty) return;
      final batch = FirebaseFirestore.instance.batch();
      final metrics = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('metrics_daily');
      for (final MapEntry(key: day, :value) in days.entries) {
        batch.set(metrics.doc(day), {
          'vo2_max': {
            'avg': value,
            'unit': 'ml/kg/min',
            'source': 'apple_health',
            'syncedAt': FieldValue.serverTimestamp(),
          },
        }, SetOptions(merge: true));
      }
      await batch.commit();
    } on MissingPluginException {
      // Builds before the native reader existed.
    } catch (error) {
      debugPrint('VO2 max sync failed: $error');
    }
  }
}
