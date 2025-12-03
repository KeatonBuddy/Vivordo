import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:vivordo_health/src/utils/toast.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  //email sign in
  static Future<void> emailSignup({
    required String emailAddress,
    required String password,
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
      await Future.delayed(const Duration(seconds: 1));
      if (context.mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (BuildContext context) => nextPage),
        );
      }
    } on FirebaseAuthException catch (e) {
      //basic password validation - should we make it more complicated?
      if (e.code == 'weak-password') {
        const message = 'Password should be at least 6 characters';
        print(e);
        ToastMessages.authMessage(message: message);
      } else if (e.code == 'email-already-in-use') {
        const message = 'The account already exists for that email.';
        print(e);
        ToastMessages.authMessage(message: message);
      }
      //store user information in firestore
    } catch (e) {
      print(e);
    }
  }

  //email sign up
  static Future<void> emailLogin({
    required String emailAddress,
    required String password,
    required BuildContext context,
    required Widget nextPage,
  }) async {
    try {
      //add validation for the email and password
      //successful sign in
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailAddress,
        password: password,
      );
      await Future.delayed(const Duration(seconds: 1));
      if (context.mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (BuildContext context) => nextPage),
        );
      }
    } on FirebaseAuthException catch (e) {
      //invalid credentials
      print(e);
      //should i take extra steps to figure out if its specifcally wrong email or password?
      if (e.code == 'invalid-credential') {
        const message = 'Invalid email or password';
        print(e);
        ToastMessages.authMessage(message: message);
      }
      //log any other errors here - crashlytics?
      //store user information in firestore
    } catch (e) {
      print(e); //log this - crashlytics?
    }
  }

  //email signout
}
