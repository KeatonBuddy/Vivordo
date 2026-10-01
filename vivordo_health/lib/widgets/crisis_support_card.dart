import 'package:flutter/material.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';

import 'privacy_support_links.dart';

// Phrases that show crisis resources immediately, before (and regardless of)
// the model's reply. False positives only cost an extra card; a miss is still
// caught by the model's `crisis` flag.
final _crisisPattern = RegExp(
  r"\b(suicid\w*|kill(ing)? my ?self|end(ing)? my life|end it all|"
  r"take my (own )?life|want(ed)? to die|wanna die|better off dead|"
  r"(don['’]?t|do not) want to (live|be alive|be here anymore)|no reason to live|"
  r"self[- ]?harm\w*|(hurt(ing)?|cut(ting)?) my ?self|overdos\w*)\b",
  caseSensitive: false,
);

bool mentionsCrisis(String text) => _crisisPattern.hasMatch(text);

/// A national crisis line for the device's region, or null when unknown (the
/// card then points to findahelpline.com, which covers every country).
({String label, Uri uri})? crisisLineFor(String? countryCode) =>
    switch (countryCode?.toUpperCase()) {
      'US' || 'CA' => (label: 'Call or text 988', uri: Uri.parse('tel:988')),
      'GB' ||
      'IE' => (label: 'Call Samaritans 116 123', uri: Uri.parse('tel:116123')),
      'AU' => (label: 'Call Lifeline 13 11 14', uri: Uri.parse('tel:131114')),
      'NZ' => (label: 'Call or text 1737', uri: Uri.parse('tel:1737')),
      'IN' => (label: 'Call Tele-MANAS 14416', uri: Uri.parse('tel:14416')),
      _ => null,
    };

class CrisisSupportCard extends StatelessWidget {
  const CrisisSupportCard({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final line = crisisLineFor(
      WidgetsBinding.instance.platformDispatcher.locale.countryCode,
    );
    return Semantics(
      container: true,
      child: Container(
        margin: const EdgeInsets.only(left: 10, right: 10, bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: VivordoTheme.brand.withValues(alpha: .35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You don’t have to handle this alone',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'If you’re in danger, might act on thoughts of harming yourself, '
              'or this is a medical emergency, call your local emergency number '
              'now. Talking to a crisis line is free and confidential.',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (line != null)
                  FilledButton.icon(
                    onPressed: () => openVivordoLink(context, line.uri),
                    icon: const Icon(Icons.call_rounded, size: 18),
                    label: Text(line.label),
                  ),
                OutlinedButton.icon(
                  onPressed: () => openVivordoLink(
                    context,
                    Uri.parse('https://findahelpline.com'),
                  ),
                  icon: const Icon(Icons.public_rounded, size: 18),
                  label: const Text('Find a helpline'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
