import 'package:flutter/material.dart';

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

  Future<void> _submit() async {
    if (_submitting || _reason == null) return;
    final details = _reason == 'other' ? _details.text.trim() : '';
    if (_reason == 'other' && details.isEmpty) {
      setState(
        () => _error = 'Please describe why you are reporting this post.',
      );
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
          _error = 'Could not send your report. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_submitting,
    child: SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24,
          12,
          24,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.isComment
                        ? 'Report comment'
                        : widget.isProfile
                        ? 'Report profile'
                        : 'Report post',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: _submitting
                      ? null
                      : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Text(
              widget.isComment
                  ? 'Why are you reporting this comment? Your report is not shared with its author.'
                  : widget.isProfile
                  ? 'Why are you reporting this profile? Your report is not shared with this person.'
                  : 'Why are you reporting this post? Your report is not shared with the person who posted it.',
            ),
            const SizedBox(height: 16),
            for (final reason in postReportReasons.entries)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  _reason == reason.key
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                title: Text(reason.value),
                selected: _reason == reason.key,
                enabled: !_submitting,
                onTap: () => setState(() {
                  _reason = reason.key;
                  _error = null;
                }),
              ),
            if (_reason == 'other')
              TextField(
                controller: _details,
                enabled: !_submitting,
                maxLength: 1000,
                minLines: 3,
                maxLines: 5,
                decoration: InputDecoration(
                  labelText: 'Tell us more',
                  hintText: widget.isProfile
                      ? 'Describe the issue with this profile'
                      : 'Describe the issue with this post',
                  border: const OutlineInputBorder(),
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _submitting || _reason == null ? null : _submit,
              child: Text(_submitting ? 'Sending…' : 'Submit report'),
            ),
          ],
        ),
      ),
    ),
  );
}
