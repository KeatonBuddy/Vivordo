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
