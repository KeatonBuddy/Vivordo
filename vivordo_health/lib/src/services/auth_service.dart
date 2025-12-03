import 'package:firebase_auth/firebase_auth.dart';
import 'package:vivordo_health/src/utils/toast.dart';

class AuthService {
  //email sign in
  static Future<void> emailSignup({
    required String emailAddress,
    required String password,
  }) async {
    try {
      final credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: emailAddress,
            password: password,
          );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'weak-password') {
        const message = 'The password provided is too weak.';
        print(message);
        ToastMessages.authMessage(message: message);
        //what makes password too weak?
      } else if (e.code == 'email-already-in-use') {
        const message = 'The account already exists for that email.';
        print(message);
        ToastMessages.authMessage(message: message);
      }
      //navigate to the next page
      //store user information in firestore
    } catch (e) {
      print(e);
    }
  }

  //email sign up

  //email
}
