import 'package:flutter/material.dart';

import '../theme/vivordo_theme.dart';
import 'apple_ui.dart';

const postReportReasons = <String, String>{
  'harassment': 'Harassment or bullying',
  'inappropriate_content': 'Inappropriate content',
  'spam': 'Spam or scams',
  'privacy': 'Privacy concern',
  'other': 'Other',
};

class ReportPostSheet extends StatefulWidget {
  const ReportPostSheet({
    super.key,
    required this.onSubmit,
    this.isProfile = false,
    this.isComment = false,
  });
  final bool isProfile;
  final bool isComment;

  final Future<void> Function(String reason, String details) onSubmit;

  @override
  State<ReportPostSheet> createState() => _ReportPostSheetState();
}

class _ReportPostSheetState extends State<ReportPostSheet> {
  final _details = TextEditingController();
  String? _reason;
  String? _error;
  bool _submitting = false;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  String get _noun => widget.isComment
      ? 'comment'
      : widget.isProfile
      ? 'profile'
      : 'post';

  Future<void> _submit() async {
    if (_submitting || _reason == null) return;
    final details = _reason == 'other' ? _details.text.trim() : '';
    if (_reason == 'other' && details.isEmpty) {
      setState(() => _error = "Describe why you're reporting this $_noun.");
      return;
    }
    if (details.length > 1000) {
      setState(() => _error = 'Keep it under 1,000 characters.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.onSubmit(_reason!, details);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = "Couldn't send your report. Try again.";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return PopScope(
      canPop: !_submitting,
      child: AppleFormSheet(
        title: 'Report $_noun',
        doneLabel: 'Send',
        busy: _submitting,
        onDone: _reason == null ? null : _submit,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
            child: Text(
              widget.isComment
                  ? "Why are you reporting this comment? Your report isn't shared with its author."
                  : widget.isProfile
                  ? "Why are you reporting this profile? Your report isn't shared with this person."
                  : "Why are you reporting this post? Your report isn't shared with the person who posted it.",
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: colors.textSecondary,
              ),
            ),
          ),
          AppleFormGroup(
            children: [
              for (final reason in postReportReasons.entries)
                AppleChoiceRow(
                  label: reason.value,
                  selected: _reason == reason.key,
                  onTap: _submitting
                      ? null
                      : () => setState(() {
                          _reason = reason.key;
                          _error = null;
                        }),
                ),
            ],
          ),
          if (_reason == 'other')
            AppleFormGroup(
              header: 'Tell us more',
              children: [
                AppleFormTextRow(
                  controller: _details,
                  enabled: !_submitting,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  placeholder: 'Describe the issue with this $_noun',
                ),
              ],
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text(
                _error!,
                style: const TextStyle(fontSize: 13, color: appleRed),
              ),
            ),
        ],
      ),
    );
  }
}
