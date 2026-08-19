import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum WhoopBleStatus {
  unpaired,
  scanning,
  connecting,
  connected,
  disconnected,
  unavailable,
  error,
}

@immutable
class WhoopBleState {
  const WhoopBleState({
    required this.status,
    this.deviceName,
    this.bpm,
    this.lastReadingAt,
    this.message,
  });

  final WhoopBleStatus status;
  final String? deviceName;
  final int? bpm;
  final DateTime? lastReadingAt;
  final String? message;

  bool get isPaired => deviceName != null;
  bool get isConnected => status == WhoopBleStatus.connected;

  bool get hasFreshReading {
    final readingAt = lastReadingAt;
    return readingAt != null &&
        DateTime.now().difference(readingAt) <=
            WhoopBleHeartRateService.freshReadingWindow;
  }
}

@immutable
class WhoopBleDevice {
  const WhoopBleDevice({
    required this.id,
    required this.name,
    required this.rssi,
  });

  final String id;
  final String name;
  final int rssi;
}

/// Receives the standard Bluetooth Heart Rate Service broadcast from WHOOP.
///
/// Live packets remain in memory for immediate UI updates. Firestore receives
/// one-minute aggregates every five minutes so continuous monitoring does not
/// create a write for every Bluetooth notification.
class WhoopBleHeartRateService {
  WhoopBleHeartRateService._();

  static final WhoopBleHeartRateService instance = WhoopBleHeartRateService._();

  static const freshReadingWindow = Duration(minutes: 5);
  static const _flushInterval = Duration(minutes: 5);
  static const _deviceIdKey = 'whoop_ble_device_id';
  static const _deviceNameKey = 'whoop_ble_device_name';
  static const _ownerUidKey = 'whoop_ble_owner_uid';
  static final Uuid _heartRateService = Uuid.parse(
    '0000180d-0000-1000-8000-00805f9b34fb',
  );
  static final Uuid _heartRateMeasurement = Uuid.parse(
    '00002a37-0000-1000-8000-00805f9b34fb',
  );

  final FlutterReactiveBle _ble = FlutterReactiveBle();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final ValueNotifier<WhoopBleState> state = ValueNotifier(
    const WhoopBleState(status: WhoopBleStatus.unpaired),
  );
  final Map<DateTime, _MinuteBucket> _pendingBuckets = {};
  final Map<DateTime, _MinuteBucket> _sessionBuckets = {};

  StreamSubscription<DiscoveredDevice>? _scanSubscription;
  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;
  StreamSubscription<List<int>>? _measurementSubscription;
  Timer? _flushTimer;
  Timer? _reconnectTimer;
  Future<void>? _loadPairingFuture;
  String? _deviceId;
  String? _deviceName;
  bool _shouldMonitor = false;
  bool _isFlushing = false;

  Future<void> _loadPairing() {
    return _loadPairingFuture ??= () async {
      final values = await Future.wait([
        _storage.read(key: _deviceIdKey),
        _storage.read(key: _deviceNameKey),
        _storage.read(key: _ownerUidKey),
      ]);
      if (values[2] != FirebaseAuth.instance.currentUser?.uid) return;
      _deviceId = values[0];
      _deviceName = values[1];
      if (_deviceId != null) {
        state.value = WhoopBleState(
          status: WhoopBleStatus.disconnected,
          deviceName: _displayName,
        );
      }
    }();
  }

  String get _displayName {
    final name = _deviceName?.trim();
    return name == null || name.isEmpty ? 'WHOOP' : name;
  }

  Future<List<WhoopBleDevice>> scanForDevices({
    Duration duration = const Duration(seconds: 8),
  }) async {
    await _loadPairing();
    _ensurePlatformSupport();
    await _scanSubscription?.cancel();
    final devices = <String, WhoopBleDevice>{};
    state.value = WhoopBleState(
      status: WhoopBleStatus.scanning,
      deviceName: _deviceId == null ? null : _displayName,
    );
    try {
      _scanSubscription = _ble
          .scanForDevices(
            withServices: [_heartRateService],
            scanMode: ScanMode.lowLatency,
            requireLocationServicesEnabled: false,
          )
          .listen((device) {
            final name = device.name.trim().isEmpty
                ? 'Heart-rate monitor'
                : device.name.trim();
            devices[device.id] = WhoopBleDevice(
              id: device.id,
              name: name,
              rssi: device.rssi,
            );
          });
      await Future<void>.delayed(duration);
      return devices.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi));
    } finally {
      await _scanSubscription?.cancel();
      _scanSubscription = null;
      if (state.value.status == WhoopBleStatus.scanning) {
        state.value = WhoopBleState(
          status: _deviceId == null
              ? WhoopBleStatus.unpaired
              : WhoopBleStatus.disconnected,
          deviceName: _deviceId == null ? null : _displayName,
        );
      }
    }
  }

  Future<void> pairAndStart(WhoopBleDevice device) async {
    _ensurePlatformSupport();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Sign in before pairing a WHOOP.');
    _deviceId = device.id;
    _deviceName = device.name;
    await Future.wait([
      _storage.write(key: _deviceIdKey, value: device.id),
      _storage.write(key: _deviceNameKey, value: device.name),
      _storage.write(key: _ownerUidKey, value: uid),
    ]);
    await startIfPaired();
  }

  /// Reconnects a previously selected WHOOP without prompting for permissions.
  Future<void> startIfPaired() async {
    await _loadPairing();
    if (_deviceId == null || _connectionSubscription != null) return;
    try {
      _ensurePlatformSupport();
    } catch (error) {
      state.value = WhoopBleState(
        status: WhoopBleStatus.unavailable,
        deviceName: _displayName,
        message: error.toString().replaceFirst('Bad state: ', ''),
      );
      return;
    }
    _shouldMonitor = true;
    await _connect();
  }

  Future<void> _connect() async {
    final deviceId = _deviceId;
    if (!_shouldMonitor ||
        deviceId == null ||
        _connectionSubscription != null) {
      return;
    }
    _reconnectTimer?.cancel();
    state.value = WhoopBleState(
      status: WhoopBleStatus.connecting,
      deviceName: _displayName,
      bpm: state.value.bpm,
      lastReadingAt: state.value.lastReadingAt,
    );
    _connectionSubscription = _ble
        .connectToDevice(
          id: deviceId,
          servicesWithCharacteristicsToDiscover: {
            _heartRateService: [_heartRateMeasurement],
          },
          connectionTimeout: const Duration(seconds: 15),
        )
        .listen(
          (update) async {
            switch (update.connectionState) {
              case DeviceConnectionState.connected:
                state.value = WhoopBleState(
                  status: WhoopBleStatus.connected,
                  deviceName: _displayName,
                  bpm: state.value.bpm,
                  lastReadingAt: state.value.lastReadingAt,
                );
                _startFlushTimer();
                await _subscribeToHeartRate(deviceId);
              case DeviceConnectionState.disconnected:
                await _handleDisconnect();
              case DeviceConnectionState.connecting:
              case DeviceConnectionState.disconnecting:
                break;
            }
          },
          onError: (Object error) async {
            await _handleDisconnect(message: 'WHOOP Bluetooth disconnected.');
          },
          onDone: _handleDisconnect,
        );
  }

  Future<void> _subscribeToHeartRate(String deviceId) async {
    await _measurementSubscription?.cancel();
    final characteristic = QualifiedCharacteristic(
      serviceId: _heartRateService,
      characteristicId: _heartRateMeasurement,
      deviceId: deviceId,
    );
    _measurementSubscription = _ble
        .subscribeToCharacteristic(characteristic)
        .listen(
          _handleMeasurement,
          onError: (Object error) async {
            await _handleDisconnect(
              message: 'Live heart-rate notifications stopped.',
            );
          },
        );
  }

  void _handleMeasurement(List<int> value) {
    final bpm = parseHeartRateMeasurement(value);
    if (bpm == null || bpm < 25 || bpm > 250) return;
    final now = DateTime.now();
    final minute = DateTime(now.year, now.month, now.day, now.hour, now.minute);
    _pendingBuckets.putIfAbsent(minute, _MinuteBucket.new).add(bpm);
    _sessionBuckets.putIfAbsent(minute, _MinuteBucket.new).add(bpm);
    if (_sessionBuckets.length > 1440) {
      final oldest = _sessionBuckets.keys.reduce(
        (a, b) => a.isBefore(b) ? a : b,
      );
      _sessionBuckets.remove(oldest);
    }
    state.value = WhoopBleState(
      status: WhoopBleStatus.connected,
      deviceName: _displayName,
      bpm: bpm,
      lastReadingAt: now,
    );
  }

  @visibleForTesting
  static int? parseHeartRateMeasurement(List<int> value) {
    if (value.length < 2) return null;
    final is16Bit = value.first & 0x01 != 0;
    if (!is16Bit) return value[1];
    if (value.length < 3) return null;
    return value[1] | (value[2] << 8);
  }

  void _startFlushTimer() {
    _flushTimer ??= Timer.periodic(_flushInterval, (_) => unawaited(flush()));
  }

  Future<void> flush() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (_isFlushing || uid == null || _pendingBuckets.isEmpty) return;
    _isFlushing = true;
    final pending = <DateTime, _MinuteBucket>{
      for (final entry in _pendingBuckets.entries)
        entry.key: (_sessionBuckets[entry.key] ?? entry.value).copy(),
    };
    _pendingBuckets.clear();
    try {
      final grouped = <String, Map<DateTime, _MinuteBucket>>{};
      for (final entry in pending.entries) {
        grouped.putIfAbsent(_dayKey(entry.key), () => {})[entry.key] =
            entry.value;
      }
      for (final entry in grouped.entries) {
        await _writeDay(uid, entry.key, entry.value);
      }
    } catch (_) {
      for (final entry in pending.entries) {
        _pendingBuckets
            .putIfAbsent(entry.key, _MinuteBucket.new)
            .merge(entry.value);
      }
      rethrow;
    } finally {
      _isFlushing = false;
    }
  }

  Future<void> _writeDay(
    String uid,
    String day,
    Map<DateTime, _MinuteBucket> pending,
  ) async {
    final reference = _db
        .collection('users')
        .doc(uid)
        .collection('metrics_daily')
        .doc(day);
    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(reference);
      final data = snapshot.data();
      final sources = data?['heart_rate_sources'] as Map?;
      final existing = sources?['whoop_ble'] as Map?;
      final entriesByMinute = <int, Map<String, dynamic>>{};
      final existingEntries = existing?['entries'];
      if (existingEntries is List) {
        for (final raw in existingEntries) {
          if (raw is! Map || raw['timestamp'] is! Timestamp) continue;
          final timestamp = (raw['timestamp'] as Timestamp).toDate();
          entriesByMinute[_minuteKey(timestamp)] = Map<String, dynamic>.from(
            raw,
          );
        }
      }
      for (final entry in pending.entries) {
        entriesByMinute[_minuteKey(entry.key)] = {
          'bpm': entry.value.average,
          'min': entry.value.minimum,
          'max': entry.value.maximum,
          'timestamp': Timestamp.fromDate(entry.key),
        };
      }
      final entries = entriesByMinute.values.toList()
        ..sort((a, b) {
          final aTime = a['timestamp'] as Timestamp;
          final bTime = b['timestamp'] as Timestamp;
          return aTime.compareTo(bTime);
        });
      if (entries.length > 1440) {
        entries.removeRange(0, entries.length - 1440);
      }
      final bpms = entries
          .map((entry) => (entry['bpm'] as num).toDouble())
          .toList();
      final minimums = entries
          .map(
            (entry) =>
                (entry['min'] as num?)?.toDouble() ??
                (entry['bpm'] as num).toDouble(),
          )
          .toList();
      final maximums = entries
          .map(
            (entry) =>
                (entry['max'] as num?)?.toDouble() ??
                (entry['bpm'] as num).toDouble(),
          )
          .toList();
      final latestAt = entries.last['timestamp'] as Timestamp;
      final payload = <String, dynamic>{
        'avg': bpms.reduce((a, b) => a + b) / bpms.length,
        'min': minimums.reduce(math.min),
        'max': maximums.reduce(math.max),
        'count': entries.length,
        'unit': 'bpm',
        'dimension': 'cardiovascular',
        'entries': entries,
        'lastReadingAt': latestAt,
        'source': 'whoop_ble',
        'syncedAt': FieldValue.serverTimestamp(),
      };
      transaction.set(reference, {
        'heart_rate_sources': {'whoop_ble': payload},
        'heart_rate': payload,
        'date': day,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  Future<void> _handleDisconnect({String? message}) async {
    final measurement = _measurementSubscription;
    _measurementSubscription = null;
    if (measurement != null) unawaited(measurement.cancel());
    final connection = _connectionSubscription;
    _connectionSubscription = null;
    if (connection != null) unawaited(connection.cancel());
    if (_deviceId != null) {
      state.value = WhoopBleState(
        status: WhoopBleStatus.disconnected,
        deviceName: _displayName,
        bpm: state.value.bpm,
        lastReadingAt: state.value.lastReadingAt,
        message: message,
      );
    }
    if (_shouldMonitor && _deviceId != null) {
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(
        const Duration(seconds: 8),
        () => unawaited(_connect()),
      );
    }
  }

  Future<void> stop({bool clearPairing = false}) async {
    _shouldMonitor = false;
    _reconnectTimer?.cancel();
    _flushTimer?.cancel();
    _flushTimer = null;
    await flush().catchError((Object _) {});
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    await _measurementSubscription?.cancel();
    _measurementSubscription = null;
    final connection = _connectionSubscription;
    _connectionSubscription = null;
    if (connection != null) await connection.cancel();
    if (clearPairing) {
      await Future.wait([
        _storage.delete(key: _deviceIdKey),
        _storage.delete(key: _deviceNameKey),
        _storage.delete(key: _ownerUidKey),
      ]);
      _deviceId = null;
      _deviceName = null;
      _pendingBuckets.clear();
      _sessionBuckets.clear();
      state.value = const WhoopBleState(status: WhoopBleStatus.unpaired);
    } else if (_deviceId != null) {
      state.value = WhoopBleState(
        status: WhoopBleStatus.disconnected,
        deviceName: _displayName,
        bpm: state.value.bpm,
        lastReadingAt: state.value.lastReadingAt,
      );
    }
  }

  Future<void> handleSignedOut() async {
    _pendingBuckets.clear();
    _sessionBuckets.clear();
    await stop();
    _deviceId = null;
    _deviceName = null;
    _loadPairingFuture = null;
    state.value = const WhoopBleState(status: WhoopBleStatus.unpaired);
  }

  void _ensurePlatformSupport() {
    if (!Platform.isIOS) {
      throw StateError(
        'Live WHOOP Bluetooth monitoring is currently available on iPhone only.',
      );
    }
  }

  static String _dayKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static int _minuteKey(DateTime value) =>
      value.millisecondsSinceEpoch ~/ Duration.millisecondsPerMinute;
}

class _MinuteBucket {
  int sum = 0;
  int count = 0;
  int minimum = 1000;
  int maximum = 0;

  int get average => count == 0 ? 0 : (sum / count).round();

  void add(int bpm) {
    sum += bpm;
    count++;
    minimum = math.min(minimum, bpm);
    maximum = math.max(maximum, bpm);
  }

  void merge(_MinuteBucket other) {
    sum += other.sum;
    count += other.count;
    minimum = math.min(minimum, other.minimum);
    maximum = math.max(maximum, other.maximum);
  }

  _MinuteBucket copy() {
    final result = _MinuteBucket();
    result.sum = sum;
    result.count = count;
    result.minimum = minimum;
    result.maximum = maximum;
    return result;
  }
}
