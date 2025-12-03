import 'package:fluttertoast/fluttertoast.dart';

class ToastMessages {
  static Future<bool?> authMessage({required String message}) async {
    return await Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
    );
  }
}
