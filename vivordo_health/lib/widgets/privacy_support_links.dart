import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Could not open link'),
      content: SelectableText(
        uri.scheme == 'mailto'
            ? 'You can email us at ${uri.path}. Copy this address into your preferred email app.'
            : 'Please try again, or copy this address into your browser:\n$uri',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
