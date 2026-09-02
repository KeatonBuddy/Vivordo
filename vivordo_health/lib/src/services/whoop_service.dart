import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:vivordo_health/src/services/whoop_ble_heart_rate_service.dart';
import 'package:vivordo_health/src/utils/whoop_authorization.dart';
import 'package:vivordo_health/src/utils/whoop_sync_schedule.dart';

/// WHOOP account integration backed by Firebase Functions.
///
/// OAuth codes, client credentials, and user tokens remain on the backend.
/// The app receives only the final success or error callback.
class WhoopService {
  WhoopService._();

  static final WhoopService instance = WhoopService._();

  static const String _callbackScheme = 'vivordo-whoop';
  static const String _automaticSlotStoragePrefix =
      'whoop_automatic_sync_slot_';
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  bool? _connectedCache;
  String? _connectedCacheUid;
  Future<void>? _activeSync;
  Future<void>? _activeBackgroundSync;
  bool _activeSyncForced = false;
  String? _automaticSlotCacheUid;
  String? _completedAutomaticSlot;
  bool _automaticSlotLoaded = false;

  Future<void> connect() async {
    final connection = await _functions
        .httpsCallable('beginWhoopConnection')
        .call<Map<String, dynamic>>();
    final authorizationUrl = connection.data['authorizationUrl'] as String?;
    if (authorizationUrl == null || authorizationUrl.isEmpty) {
      throw StateError('WHOOP has not been configured for this build.');
    }

    final callback = await FlutterWebAuth2.authenticate(
      url: authorizationUrl,
      callbackUrlScheme: _callbackScheme,
    );
    final callbackUri = Uri.parse(callback);
    final error = callbackUri.queryParameters['error'];
    if (error != null) {
      throw StateError(
        callbackUri.queryParameters['error_description'] ??
            'WHOOP authorization was cancelled.',
      );
    }
    if (callbackUri.queryParameters['status'] != 'success') {
      throw StateError('WHOOP did not complete authorization.');
    }

    _connectedCache = true;
    _connectedCacheUid = FirebaseAuth.instance.currentUser?.uid;
    await sync(daysBack: 30, force: true);
  }

  /// Syncs WHOOP sleep. Explicit refreshes force the requested history window;
  /// lifecycle refreshes follow the backend's morning/midday schedule.
  Future<void> sync({int daysBack = 30, bool force = true}) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return Future.error(StateError('Sign in before syncing WHOOP.'));
    }
    final activeSync = _activeSync;
    if (activeSync != null) {
      if (!force || _activeSyncForced) return activeSync;
      return activeSync
          .catchError((Object _) {})
          .then((_) => sync(daysBack: daysBack, force: true));
    }

    final boundedDays = daysBack.clamp(1, 30);
    final request = _performSync(uid: uid, daysBack: boundedDays, force: force);
    _activeSync = request;
    _activeSyncForced = force;
    return request.whenComplete(() {
      if (identical(_activeSync, request)) {
        _activeSync = null;
        _activeSyncForced = false;
      }
    });
  }

  Future<void> disconnect({required bool deleteImportedData}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    await _functions.httpsCallable('disconnectWhoop').call<void>({
      'deleteImportedData': deleteImportedData,
    });
    await _clearLocalConnection(uid);
  }

  Future<void> _performSync({
    required String uid,
    required int daysBack,
    required bool force,
  }) async {
    try {
      await _functions.httpsCallable('syncWhoop').call<void>({
        'daysBack': daysBack,
        'force': force,
        'timezoneOffsetMinutes': DateTime.now().timeZoneOffset.inMinutes,
      });
      await _recordCurrentAutomaticSlot(uid);
    } on FirebaseFunctionsException catch (error) {
      if (whoopReconnectRequired(error.code, error.details)) {
        await _clearLocalConnection(uid);
      }
      rethrow;
    }
  }

  Future<void> _clearLocalConnection(String? uid) async {
    try {
      await WhoopBleHeartRateService.instance.clearWhoopPairing();
    } catch (error) {
      debugPrint('[WhoopService] Could not clear WHOOP pairing: $error');
    }
    if (uid != null) {
      try {
        await _storage.delete(key: '$_automaticSlotStoragePrefix$uid');
      } catch (error) {
        debugPrint('[WhoopService] Could not clear local sync slot: $error');
      }
    }
    _connectedCache = false;
    _connectedCacheUid = uid;
    _clearAutomaticSlotCache();
  }

  Future<void> syncInBackground({int daysBack = 1}) {
    final active = _activeBackgroundSync;
    if (active != null) return active;
    final request = _syncIfConnected(daysBack: daysBack).catchError((
      Object error,
    ) {
      debugPrint('[WhoopService] Background sync skipped: $error');
    });
    _activeBackgroundSync = request;
    return request.whenComplete(() {
      if (identical(_activeBackgroundSync, request)) {
        _activeBackgroundSync = null;
      }
    });
  }

  Future<void> _syncIfConnected({required int daysBack}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    var connected = _connectedCacheUid == uid ? _connectedCache : null;
    if (connected == null) {
      final user = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      connected = user.data()?['whoopConnected'] == true;
      _connectedCache = connected;
      _connectedCacheUid = uid;
    }
    if (connected) {
      await WhoopBleHeartRateService.instance.startIfPaired();
      if (await _automaticSlotAlreadyCompleted(uid)) return;
      await sync(daysBack: daysBack, force: false);
    }
  }

  Future<bool> _automaticSlotAlreadyCompleted(String uid) async {
    final currentSlot = whoopAutomaticSyncSlotKey(uid, DateTime.now());
    if (currentSlot == null) return true;
    if (_automaticSlotCacheUid != uid) {
      _automaticSlotCacheUid = uid;
      _completedAutomaticSlot = null;
      _automaticSlotLoaded = false;
    }
    if (!_automaticSlotLoaded) {
      try {
        _completedAutomaticSlot = await _storage.read(
          key: '$_automaticSlotStoragePrefix$uid',
        );
      } catch (error) {
        // Continue to the server check if Keychain is unavailable. Successful
        // syncs still activate the in-memory gate for the current session.
        debugPrint('[WhoopService] Could not read local sync slot: $error');
      }
      _automaticSlotLoaded = true;
    }
    return _completedAutomaticSlot == currentSlot;
  }

  Future<void> _recordCurrentAutomaticSlot(String? uid) async {
    if (uid == null) return;
    final currentSlot = whoopAutomaticSyncSlotKey(uid, DateTime.now());
    if (currentSlot == null) return;
    _automaticSlotCacheUid = uid;
    _completedAutomaticSlot = currentSlot;
    _automaticSlotLoaded = true;
    try {
      await _storage.write(
        key: '$_automaticSlotStoragePrefix$uid',
        value: currentSlot,
      );
    } catch (error) {
      // Keep the in-memory gate active for this session even if Keychain is
      // temporarily unavailable. The backend schedule remains authoritative.
      debugPrint('[WhoopService] Could not persist local sync slot: $error');
    }
  }

  void _clearAutomaticSlotCache() {
    _automaticSlotCacheUid = null;
    _completedAutomaticSlot = null;
    _automaticSlotLoaded = false;
  }
}
