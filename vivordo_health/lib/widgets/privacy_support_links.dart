import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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

/// Uses the published policies, so updates do not require an app release.
class PrivacySupportLinks extends StatelessWidget {
  const PrivacySupportLinks({super.key});

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      ListTile(
        leading: const Icon(Icons.privacy_tip_outlined),
        title: const Text('Privacy Policy'),
        trailing: const Icon(Icons.open_in_new),
        onTap: () => openVivordoLink(context, Uri.parse(vivordoPrivacyUrl)),
      ),
      const Divider(height: 1),
      ListTile(
        leading: const Icon(Icons.description_outlined),
        title: const Text('Terms & Conditions'),
        trailing: const Icon(Icons.open_in_new),
        onTap: () => openVivordoLink(context, Uri.parse(vivordoTermsUrl)),
      ),
      const Divider(height: 1),
      ListTile(
        leading: const Icon(Icons.support_agent),
        title: const Text('Contact Support'),
        subtitle: const Text(vivordoSupportEmail),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => openVivordoLink(
          context,
          Uri(scheme: 'mailto', path: vivordoSupportEmail),
        ),
      ),
    ],
  );
}
