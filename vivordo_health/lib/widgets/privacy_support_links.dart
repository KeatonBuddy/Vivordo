import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'apple_ui.dart';

/// Published policies, so updates do not require an app release.
const vivordoPrivacyUrl = 'https://vivordo.com/privacy';
const vivordoTermsUrl = 'https://vivordo.com/terms';
const vivordoSupportEmail = 'contact.vivordo@gmail.com';

Future<void> openVivordoLink(BuildContext context, Uri uri) async {
  try {
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
  } catch (_) {
    // Keep the destination accessible when the device has no URL handler.
  }
  if (!context.mounted) return;
  final isEmail = uri.scheme == 'mailto';
  await showAppleAlert<void>(
    context,
    title: "Couldn't open link",
    message: isEmail
        ? 'You can email us at this address from your email app.'
        : 'Try again, or copy this address into your browser.',
    content: SelectableText(
      isEmail ? uri.path : '$uri',
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    ),
    actions: const [AppleAlertAction('OK', null, bold: true)],
  );
}

/// "By continuing you agree to the Terms and Privacy Policy", both linked:
/// shown wherever an account can be created, so everyone agrees to the
/// Terms (including Circle's rules on content) before using the app.
class TermsAgreement extends StatelessWidget {
  const TermsAgreement({super.key, this.color = const Color(0xFF8E8E93)});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(color: color, fontSize: 12, height: 1.4);
    Widget link(String label, String url) => GestureDetector(
      onTap: () => openVivordoLink(context, Uri.parse(url)),
      child: Text(
        label,
        style: style.copyWith(
          fontWeight: FontWeight.w700,
          decoration: TextDecoration.underline,
          decorationColor: color,
        ),
      ),
    );
    return Semantics(
      container: true,
      child: Wrap(
        alignment: WrapAlignment.center,
        children: [
          Text('By continuing you agree to the ', style: style),
          link('Terms', vivordoTermsUrl),
          Text(' and ', style: style),
          link('Privacy Policy', vivordoPrivacyUrl),
          Text('.', style: style),
        ],
      ),
    );
  }
}
