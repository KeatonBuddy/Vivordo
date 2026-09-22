import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:vivordo_health/src/services/calendar_service.dart';
import 'package:vivordo_health/src/services/home_widget_service.dart';
import 'package:vivordo_health/src/services/notification_service.dart';
import 'package:vivordo_health/src/services/outlook_calendar_service.dart';
import 'package:vivordo_health/src/services/whoop_ble_heart_rate_service.dart';
import 'package:vivordo_health/src/services/workout_live_activity_service.dart';

class AccountDeletionService {
  AccountDeletionService._();

  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFunctions _functions = FirebaseFunctions.instance;
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  static bool get requiresPassword {
    final user = _auth.currentUser;
    return user?.providerData.any(
          (provider) => provider.providerId == 'password',
        ) ??
        false;
  }

  static Future<void> deleteAccount({String? password}) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Sign in before deleting your account.');

    final appleAuthorizationCode = await _reauthenticate(
      user,
      password: password,
    );
    if (appleAuthorizationCode != null) {
      await _auth.revokeTokenWithAuthorizationCode(appleAuthorizationCode);
    }
    await user.getIdToken(true);
    await _functions.httpsCallable('deleteVivordoAccount').call<void>({
      'confirmation': 'DELETE',
    });

    // Server deletion is authoritative. Local sign-ins, pairings, cached
    // secrets, and in-memory wearable state are removed before routing back to
    // the login screen.
    await WhoopBleHeartRateService.instance.handleSignedOut().catchError(
      (Object _) {},
    );
    await OutlookCalendarService.signOut().catchError((Object _) {});
    await CalendarService.signOut().catchError((Object _) {});
    await NotificationService().clearAfterAccountDeletion().catchError(
      (Object _) {},
    );
    await HomeWidgetService.clearAccountSnapshot();
    await WorkoutLiveActivityService.end();
    await _secureStorage.deleteAll().catchError((Object _) {});
    await _auth.signOut().catchError((Object _) {});
  }

  static Future<String?> _reauthenticate(User user, {String? password}) async {
    final providerIds = user.providerData
        .map((provider) => provider.providerId)
        .toSet();

    if (providerIds.contains('password')) {
      final email = user.email;
      if (email == null || password == null || password.isEmpty) {
        throw StateError('Enter your password to continue.');
      }
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: email, password: password),
      );
      return null;
    }

    if (providerIds.contains('google.com')) {
      await CalendarService.initialize();
      if (!GoogleSignIn.instance.supportsAuthenticate()) {
        throw StateError('Google Sign-In is not supported on this device.');
      }
      final googleUser = await GoogleSignIn.instance.authenticate();
      CalendarService.registerSignedInAccount(googleUser);
      final idToken = googleUser.authentication.idToken;
      if (idToken == null) {
        throw StateError('Google did not return a sign-in token.');
      }
      await user.reauthenticateWithCredential(
        GoogleAuthProvider.credential(idToken: idToken),
      );
      return null;
    }

    if (providerIds.contains('apple.com')) {
      final provider = AppleAuthProvider()
        ..addScope('email')
        ..addScope('name');
      final credential = await user.reauthenticateWithProvider(provider);
      final authorizationCode =
          credential.additionalUserInfo?.authorizationCode;
      if (authorizationCode == null || authorizationCode.isEmpty) {
        throw StateError(
          'Apple did not return the authorization needed to remove access. '
          'Please try again.',
        );
      }
      return authorizationCode;
    }

    throw StateError(
      'Vivordo could not find a supported sign-in method for this account.',
    );
  }
}
