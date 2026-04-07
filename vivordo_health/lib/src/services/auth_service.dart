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
        // Firebase Auth's User object is NOT automatically refreshed after
        // updateDisplayName — the local object still has displayName: null.
        // reload() forces the SDK to fetch the updated profile, then we use
        // a fresh currentUser reference so Firestore gets the correct name.
        await currentUser.reload();
        final refreshedUser = FirebaseAuth.instance.currentUser!;
        await UserService.createUser(refreshedUser);
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

  // email sign in — returns true on success, false on failure
  static Future<bool> emailLogin({
    required String emailAddress,
    required String password,
    required BuildContext context,
  }) async {
    try {
      final userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(
            email: emailAddress,
            password: password,
          );

      final currentUser = userCredential.user;
      if (currentUser == null) throw Exception('Error signing in user');

      return true; // success
    } on FirebaseAuthException catch (e) {
      if (context.mounted) {
        if (e.code == 'invalid-credential') {
          const message = 'Invalid email or password';
          SnackBars.authMessage(context: context, message: message);
        } else {
          SnackBars.authMessage(context: context, message: e.code);
        }
      }
      return false; // failure
    } catch (e) {
      print(e);
      return false;
    }
  }

  //email signout - use await FirebaseAuth.instance.signOut();
}