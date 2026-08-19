import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

/// WHOOP account integration backed by Firebase Functions.
///
/// OAuth codes, client credentials, and user tokens remain on the backend.
/// The app receives only the final success or error callback.
class WhoopService {
  WhoopService._();

  static final WhoopService instance = WhoopService._();

  static const String _callbackScheme = 'vivordo-whoop';
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  bool? _connectedCache;
  Future<void>? _activeSync;

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
    await sync(daysBack: 30);
  }

  Future<void> sync({int daysBack = 30}) {
    final activeSync = _activeSync;
    if (activeSync != null) return activeSync;

    final boundedDays = daysBack.clamp(1, 30);
    final request = _functions
        .httpsCallable('syncWhoop')
        .call<void>({'daysBack': boundedDays})
        .then((_) {});
    _activeSync = request;
    return request.whenComplete(() {
      if (identical(_activeSync, request)) _activeSync = null;
    });
  }

  Future<void> disconnect() async {
    await _functions.httpsCallable('disconnectWhoop').call<void>();
    _connectedCache = false;
  }

  Future<void> syncInBackground({int daysBack = 1}) {
    return _syncIfConnected(daysBack: daysBack).catchError((Object error) {
      debugPrint('[WhoopService] Background sync skipped: $error');
    });
  }

  Future<void> _syncIfConnected({required int daysBack}) async {
    var connected = _connectedCache;
    if (connected == null) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final user = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      connected = user.data()?['whoopConnected'] == true;
      _connectedCache = connected;
    }
    if (connected) await sync(daysBack: daysBack);
  }
}
