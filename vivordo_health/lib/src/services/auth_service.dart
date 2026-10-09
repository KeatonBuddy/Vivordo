import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:vivordo_health/src/services/calendar_service.dart';
import 'package:vivordo_health/src/services/user_service.dart';
import 'package:vivordo_health/widgets/apple_ui.dart';

//TODO(favour): log flagged items to crashlytics

class AuthService {
  //email sign up — returns true on success
  static Future<bool> emailSignup({
    required String emailAddress,
    required String password,
    required String displayName,
    String photoUrl = 'default photo url', //TODO(favour): add default photo
    required BuildContext context,
    // When provided, password-specific errors (e.g. weak-password) are
    // routed here instead of a SnackBar, so callers can surface them
    // inline next to the password field instead of as a bottom toast.
    void Function(String message)? onPasswordError,
  }) async {
    try {
      final credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: emailAddress,
            password: password,
          );
      final currentUser = credential.user;
      if (currentUser != null) {
        await currentUser.updateDisplayName(displayName);
        await currentUser.updatePhotoURL(photoUrl);
        // Firebase Auth's User object is NOT automatically refreshed after
        // updateDisplayName — the local object still has displayName: null.
        // reload() forces the SDK to fetch the updated profile, then we use
        // a fresh currentUser reference so Firestore gets the correct name.
        await currentUser.reload();
        final refreshedUser = FirebaseAuth.instance.currentUser!;
        await UserService.createUser(refreshedUser);
        // Firebase can't confirm the address is real/deliverable at signup
        // time — the only way to prove that is a link the user has to
        // actually open in their inbox. AuthGate blocks app access until
        // emailVerified is true, so this is what gates account creation on
        // a real address rather than the createUser call itself.
        await refreshedUser.sendEmailVerification();
      } else {
        throw Exception("Error creating user");
      }
      return true;
    } on FirebaseAuthException catch (e) {
      debugPrint('Email sign-up failed: ${e.code} ${e.message}');
      if (e.code == 'weak-password') {
        final message = authErrorMessage(e);
        if (onPasswordError != null) {
          onPasswordError(message);
        } else if (context.mounted) {
          _authMessage(context, message);
        }
      } else if (context.mounted) {
        _authMessage(
          context,
          authErrorMessage(
            e,
            fallback: "Couldn't create your account. Try again.",
          ),
        );
      }
    } catch (e) {
      debugPrint(e.toString());
    }
    return false;
  }

  // send password reset email — returns true on success
  static Future<bool> sendPasswordReset({
    required String emailAddress,
    required BuildContext context,
  }) async {
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: emailAddress.trim(),
      );
      return true;
    } on FirebaseAuthException catch (e) {
      debugPrint('Password reset failed: ${e.code} ${e.message}');
      if (context.mounted) {
        _authMessage(
          context,
          authErrorMessage(
            e,
            fallback: "Couldn't send the reset email. Try again.",
          ),
        );
      }
      return false;
    } catch (e) {
      debugPrint(e.toString());
      return false;
    }
  }

  // Google sign-in — returns true on success, false on failure/cancellation.
  // Firebase automatically marks a federated Google account's emailVerified
  // as true (Google already proved ownership of the address), so these
  // users skip EmailVerificationScreen entirely via AuthGate.
  static Future<bool> signInWithGoogle({required BuildContext context}) async {
    try {
      // GoogleSignIn.instance is a singleton that can only be initialized
      // once app-wide — CalendarService already owns that initialization
      // (it also configures the serverClientId needed for idToken here), so
      // reuse it rather than calling initialize() a second time.
      await CalendarService.initialize();

      if (!GoogleSignIn.instance.supportsAuthenticate()) {
        if (context.mounted) {
          _authMessage(
            context,
            "Google sign-in isn't available on this device.",
          );
        }
        return false;
      }

      final googleUser = await GoogleSignIn.instance.authenticate();
      CalendarService.registerSignedInAccount(googleUser);
      final idToken = googleUser.authentication.idToken;
      if (idToken == null) {
        throw Exception('Google Sign-In did not return an ID token');
      }

      final credential = GoogleAuthProvider.credential(idToken: idToken);
      final userCredential = await FirebaseAuth.instance.signInWithCredential(
        credential,
      );
      final user = userCredential.user;
      if (user == null) {
        throw Exception('Error signing in with Google');
      }

      if (userCredential.additionalUserInfo?.isNewUser ?? false) {
        // New accounts are asked for Calendar in onboarding, with context.
        await UserService.createUser(user);
      } else {
        // Google identity authentication does not automatically grant access
        // to Google Calendar. Request it before navigating to the home screen
        // so the first calendar load does not race the authentication event
        // stream.
        await CalendarService.authorizeCalendarAccess();
      }
      return true;
    } on GoogleSignInException catch (e) {
      // Don't show an error toast for a plain cancel — that's not a failure.
      if (e.code != GoogleSignInExceptionCode.canceled && context.mounted) {
        _authMessage(context, "Couldn't sign in with Google. Try again.");
      }
      return false;
    } on FirebaseAuthException catch (e) {
      debugPrint('Google sign-in failed: ${e.code} ${e.message}');
      if (context.mounted) {
        _authMessage(
          context,
          authErrorMessage(
            e,
            fallback: "Couldn't sign in with Google. Try again.",
          ),
        );
      }
      return false;
    } catch (e) {
      debugPrint(e.toString());
      return false;
    }
  }

  // Apple sign-in — Firebase's native Apple provider manages the secure
  // nonce and authorization flow on iOS. Apple only returns the user's name
  // the first time they authorize the app, so create the Firestore profile
  // immediately for new accounts while that information is available.
  static Future<bool> signInWithApple({required BuildContext context}) async {
    try {
      final provider = AppleAuthProvider()
        ..addScope('email')
        ..addScope('name');
      final userCredential = await FirebaseAuth.instance.signInWithProvider(
        provider,
      );
      final user = userCredential.user;
      if (user == null) {
        throw Exception('Error signing in with Apple');
      }

      if (userCredential.additionalUserInfo?.isNewUser ?? false) {
        await UserService.createUser(user);
      }
      return true;
    } on FirebaseAuthException catch (e) {
      // Closing Apple's authorization sheet is a normal cancellation, not an
      // authentication failure that needs to be surfaced to the user.
      const cancellationCodes = {
        'canceled',
        'cancelled',
        'web-context-canceled',
        'web-context-cancelled',
      };
      if (!cancellationCodes.contains(e.code) && context.mounted) {
        debugPrint('Apple sign-in failed: ${e.code} ${e.message}');
        _authMessage(
          context,
          authErrorMessage(
            e,
            fallback: "Couldn't sign in with Apple. Try again.",
          ),
        );
      }
      return false;
    } catch (e) {
      debugPrint(e.toString());
      if (context.mounted) {
        _authMessage(context, "Couldn't sign in with Apple. Try again.");
      }
      return false;
    }
  }

  // email sign in — returns true on success, false on failure
  static Future<bool> emailLogin({
    required String emailAddress,
    required String password,
    required BuildContext context,
  }) async {
    try {
      final userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: emailAddress, password: password);

      final currentUser = userCredential.user;
      if (currentUser == null) {
        throw Exception('Error signing in user');
      }
      // Sync email state on every login. If the user previously verified an
      // email change, this cleans up pendingEmail from Firestore immediately
      // so the profile screen never sees stale pending state.
      await UserService.syncEmailWithAuth();
      return true;
    } on FirebaseAuthException catch (e) {
      debugPrint('Email sign-in failed: ${e.code} ${e.message}');
      if (context.mounted) {
        _authMessage(
          context,
          authErrorMessage(e, fallback: "Couldn't sign in. Try again."),
        );
      }
      return false;
    } catch (e) {
      debugPrint(e.toString());
      return false;
    }
  }
}

/// Plain words for a [FirebaseAuthException]; never the raw code or message.
String authErrorMessage(
  FirebaseAuthException e, {
  String fallback = 'Something went wrong. Try again.',
}) => switch (e.code) {
  'wrong-password' ||
  'invalid-credential' ||
  'INVALID_LOGIN_CREDENTIALS' => "That email or password isn't right.",
  'user-not-found' => "There's no account with that email.",
  'invalid-email' => "That email address doesn't look right.",
  'email-already-in-use' => 'An account already exists with that email.',
  'weak-password' => 'Use at least 6 characters for your password.',
  'too-many-requests' => 'Too many attempts. Try again in a few minutes.',
  'network-request-failed' =>
    'No connection. Check your internet and try again.',
  'user-disabled' => 'This account has been turned off. Contact support.',
  'requires-recent-login' => 'For your security, sign in again and retry.',
  'account-exists-with-different-credential' =>
    'An account already exists with this email using a different sign-in method.',
  _ => fallback,
};

void _authMessage(BuildContext context, String message) {
  showToast(context, message, kind: ToastKind.error);
}
