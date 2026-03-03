import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:vivordo_health/src/services/user_service.dart';
import 'package:vivordo_health/src/utils/snackbar.dart';

//TODO(favour): log flagged items to crashlytics

class AuthService {
  //email sign up
  static Future<void> emailSignup({
    required String emailAddress,
    required String password,
    required String displayName,
    String photoUrl = 'default photo url', //TODO(favour): add default photo
    required BuildContext context,
    required PageController pageController,
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
        await UserService.createUser(currentUser);
      } else {
        throw Exception("Error creating user");
      }


      pageController.nextPage(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOutCubicEmphasized,
      );
    } on FirebaseAuthException catch (e) {
      if (context.mounted) {
        if (e.code == 'weak-password') {
          const message = 'Password should be at least 6 characters';
          SnackBars.authMessage(context: context, message: message);
        } else if (e.code == 'email-already-in-use') {
          const message = 'The account already exists for that email.';
          SnackBars.authMessage(context: context, message: message);
        } else {
          SnackBars.authMessage(context: context, message: e.code);
        }
      }
    } catch (e) {
      print(e);
    }
  }

  //email sign in
  static Future<void> emailLogin({
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

    } on FirebaseAuthException catch (e) {
      if (context.mounted) {
        if (e.code == 'invalid-credential') {
          const message = 'Invalid email or password';
          SnackBars.authMessage(context: context, message: message);
        } else {
          SnackBars.authMessage(context: context, message: e.code);
        }
      }
    } catch (e) {
      print(e);
    }
  }

  //email signout - use await FirebaseAuth.instance.signOut();
}
