import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:vivordo_health/src/services/user_service.dart';
import 'package:vivordo_health/src/utils/snackbar.dart';

//TODO(favour): log flagged items to crashlytics

class AuthService {
  //email sign in
  static Future<void> emailSignup({
    required String emailAddress,
    required String password,
    required String displayName,
    String photoUrl = 'default photo url', //TODO(favour): add default photo
    required BuildContext context,
    required Widget nextPage,
  }) async {
    try {
      //add validation for the email and password
      //successful signup
      final credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: emailAddress,
            password: password,
          );
      final currentUser = credential.user;
      //create firestore collection
      if (currentUser != null) {
        await currentUser.updateDisplayName(displayName);
        await currentUser.updatePhotoURL(photoUrl);
        await UserService.createUser(currentUser);
      } else {
        throw Exception("Error creating user"); //log this to crashlytics
      }

      //navigate to next page
      await Future.delayed(const Duration(seconds: 1));
      if (context.mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (BuildContext context) => nextPage),
        );
      }
    } on FirebaseAuthException catch (e) {
      //TODO: basic password validation - should we make it more complicated?
      if (context.mounted) {
        if (e.code == 'weak-password') {
          const message = 'Password should be at least 6 characters';
          print(e);
          SnackBars.authMessage(context: context, message: message);
        } else if (e.code == 'email-already-in-use') {
          const message = 'The account already exists for that email.';
          print(e);
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
    required Widget nextPage,
  }) async {
    try {
      //add validation for the email and password
      //successful sign in
      final userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: emailAddress, password: password);

      final currentUser = userCredential.user;
      if (currentUser == null) {
        throw Exception('Error signing in user');
      }

      //navigate to next page
      await Future.delayed(const Duration(seconds: 1));
      if (context.mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (BuildContext context) => nextPage),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (context.mounted) {
        //should i take extra steps to figure out if its specifcally wrong email or password?
        if (e.code == 'invalid-credential') {
          const message = 'Invalid email or password';
          SnackBars.authMessage(context: context, message: message);
        } else {
          SnackBars.authMessage(context: context, message: e.code);
        }
      }
      //log any other errors here - crashlytics?
      //store user information in firestore
    } catch (e) {
      print(e); //log this - crashlytics?
    }
  }

  //email signout - use await FirebaseAuth.instance.signOut();
}
