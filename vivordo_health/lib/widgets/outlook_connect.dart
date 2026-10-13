import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../src/services/outlook_calendar_service.dart';
import 'apple_ui.dart';

/// Connects Outlook from Settings or onboarding; true once connected. When
/// the account's organisation has to approve Vivordo first, says so and
/// offers the approval link for their IT admin. Other failures throw, for
/// the caller to report.
Future<bool> connectOutlook(BuildContext context) async {
  try {
    return await OutlookCalendarService.connect();
  } on OutlookNeedsAdminApproval {
    if (!context.mounted) return false;
    final copy = await confirmAction(
      context,
      title: 'Your organisation needs to approve Vivordo',
      message:
          'This work account can only connect apps your IT team has '
          'approved. Send them the approval link, then connect again. A '
          'personal Outlook account works without approval.',
      confirmLabel: 'Copy link for IT',
      cancelLabel: 'Not now',
      destructive: false,
    );
    if (copy) {
      await Clipboard.setData(
        const ClipboardData(text: OutlookCalendarService.adminConsentUrl),
      );
      if (context.mounted) showToast(context, 'Approval link copied.');
    }
    return false;
  }
}
