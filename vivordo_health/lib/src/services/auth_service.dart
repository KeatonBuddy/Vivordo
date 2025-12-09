import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:vivordo_health/src/services/user_service.dart';
import 'package:vivordo_health/src/utils/toast.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  //email sign in
  static Future<void> emailSignup({
    required String emailAddress,
    required String password,
    required String displayName,
    String photoUrl = 'default photo url', //change this later
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
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailAddress,
        password: password,
      );

      //navigate to next page
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

  //google sign up and log in
  //workds only on android and ios and not web
  static Future<void> googleAuth() async {
    print("google signup");
    //do we want a user with pre existing email account to be turned into a google account
    //or should i implement validation to prevent this?

    // Trigger the authentication flow
    final GoogleSignInAccount googleUser = await GoogleSignIn.instance
        .authenticate();

    // Obtain the auth details from the request
    final GoogleSignInAuthentication googleAuth = googleUser.authentication;

    // Create a new credential
    final credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
    );

    // Once signed in, return the UserCredential
    final userCred = await FirebaseAuth.instance.signInWithCredential(
      credential,
    );
    //add details to firestore
  }
}
