import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';

import '../src/utils/journal_summary.dart';
import '../theme/vivordo_theme.dart';

/// What the writing sheet hands back to be saved.
class JournalDraft {
  const JournalDraft({
    required this.text,
    required this.mood,
    required this.shared,
  });

  final String text;
  final String mood;
  final bool shared;
}

Color journalMoodColor(BuildContext context, String? mood) =>
    switch (moodTone(mood)) {
      MoodTone.good => const Color(0xFF05A956),
      MoodTone.middling => const Color(0xFFFF7A00),
      MoodTone.hard => const Color(0xFFFF3D4F),
      MoodTone.none => context.vivordoColors.border,
    };

/// Opens the writing sheet for a new entry on [date], or for [editing].
/// [onSave] persists the draft; the sheet closes only once it succeeds and
/// then resolves true. A new entry's text is kept as a draft under
/// [draftKey] until it is saved.
Future<bool?> showJournalEntrySheet(
  BuildContext context, {
  required DateTime date,
  required Future<void> Function(JournalDraft draft) onSave,
  JournalItem? editing,
  String? prompt,
  String? draftKey,
}) => showModalBottomSheet<bool>(
  context: context,
  // Above the app shell, so the floating AI button can't cover the sheet.
  useRootNavigator: true,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  barrierColor: Colors.black.withValues(alpha: .6),
  builder: (_) => JournalEntrySheet(
    date: date,
    onSave: onSave,
    editing: editing,
    prompt: prompt,
    draftKey: editing == null ? draftKey : null,
  ),
);

class JournalEntrySheet extends StatefulWidget {
  const JournalEntrySheet({
    super.key,
    required this.date,
    required this.onSave,
    this.editing,
    this.prompt,
    this.draftKey,
  });

  final DateTime date;
  final Future<void> Function(JournalDraft draft) onSave;
  final JournalItem? editing;
  final String? prompt;
  final String? draftKey;

  @override
  State<JournalEntrySheet> createState() => _JournalEntrySheetState();
}

class _JournalEntrySheetState extends State<JournalEntrySheet>
    with SingleTickerProviderStateMixin {
  static const _storage = FlutterSecureStorage();

  late final TextEditingController _text;
  late final AnimationController _shake;
  String? _mood;
  bool _shared = false;
  bool _saving = false;
  bool _moodMissing = false;
  bool _draftSaved = false;
  String? _error;
  Timer? _draftTimer;

  @override
  void initState() {
    super.initState();
    final editing = widget.editing;
    _text = TextEditingController(text: editing?.text)
      ..addListener(_textChanged);
    _mood = editing?.mood;
    _shared = editing?.shared ?? false;
    _shake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 460),
    );
    _restoreDraft();
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    _text
      ..removeListener(_textChanged)
      ..dispose();
    _shake.dispose();
    super.dispose();
  }

  Future<void> _restoreDraft() async {
    final key = widget.draftKey;
    if (key == null) return;
    try {
      final raw = await _storage.read(key: key);
      if (raw == null || !mounted || _text.text.isNotEmpty) return;
      final draft = jsonDecode(raw) as Map<String, dynamic>;
      setState(() {
        _text.text = draft['text'] as String? ?? '';
        final mood = draft['mood'] as String?;
        _mood = journalMoods.contains(mood) ? mood : null;
        _shared = draft['shared'] == true;
        _draftSaved = _text.text.isNotEmpty;
      });
    } catch (_) {
      // A missing or unreadable draft just means starting fresh.
    }
  }

  void _textChanged() {
    setState(() => _draftSaved = false);
    _scheduleDraft();
  }

  void _scheduleDraft() {
    final key = widget.draftKey;
    if (key == null) return;
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 600), () async {
      try {
        if (_text.text.trim().isEmpty) {
          await _storage.delete(key: key);
        } else {
          await _storage.write(
            key: key,
            value: jsonEncode({
              'text': _text.text,
              'mood': _mood,
              'shared': _shared,
            }),
          );
        }
        if (mounted) setState(() => _draftSaved = _text.text.isNotEmpty);
      } catch (_) {
        // Drafts are a convenience; the entry itself is saved to Firestore.
      }
    });
  }

  Future<void> _save() async {
    final text = _text.text.trim();
    if (text.isEmpty || _saving) return;
    final mood = _mood;
    if (mood == null) {
      setState(() => _moodMissing = true);
      HapticFeedback.heavyImpact();
      SemanticsService.sendAnnouncement(
        View.of(context),
        'Choose how you are feeling to save this entry',
        Directionality.of(context),
      );
      _shake.forward(from: 0);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(
        JournalDraft(text: text, mood: mood, shared: _shared),
      );
      _draftTimer?.cancel();
      final key = widget.draftKey;
      if (key != null) {
        try {
          await _storage.delete(key: key);
        } catch (_) {}
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Couldn’t save. Check your connection and try again.';
      });
    }
  }

  int get _words => RegExp(r'\S+').allMatches(_text.text).length;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final canSave = _text.text.trim().isNotEmpty && !_saving;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 160),
      padding: EdgeInsets.only(bottom: keyboard),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .94,
        ),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: colors.border,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Row(
              children: [
                TextButton(
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: colors.textSecondary),
                  ),
                ),
                Expanded(
                  child: Text(
                    DateFormat('EEEE, MMM d').format(widget.date),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: canSave ? _save : null,
                  child: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(
                          'Save',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                ),
              ],
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.manual,
                children: [
                  if (widget.prompt != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      widget.prompt!,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      for (final mood in journalMoods)
                        Expanded(child: _moodOption(context, mood)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  AnimatedBuilder(
                    animation: _shake,
                    builder: (context, child) {
                      final t = _shake.value;
                      return Transform.translate(
                        offset: Offset(
                          math.sin(t * math.pi * 6) * 10 * (1 - t),
                          0,
                        ),
                        child: child,
                      );
                    },
                    child: Text(
                      'How are you feeling?',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _moodMissing && _mood == null
                            ? journalMoodColor(context, 'Stressed')
                            : colors.textSecondary,
                        fontSize: 13,
                        fontWeight: _moodMissing && _mood == null
                            ? FontWeight.w800
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _text,
                    autofocus: widget.editing == null,
                    minLines: 8,
                    maxLines: null,
                    maxLength: 5000,
                    textCapitalization: TextCapitalization.sentences,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 16,
                      height: 1.55,
                    ),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: 'Start writing…',
                      hintStyle: TextStyle(color: colors.textSecondary),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: colors.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 6, 0),
              child: Row(
                children: [
                  Icon(
                    _shared ? Icons.groups_rounded : Icons.lock_rounded,
                    size: 16,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _shared ? 'Shared with your Circle' : 'Private to you',
                      style: TextStyle(color: colors.textSecondary),
                    ),
                  ),
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () {
                            setState(() => _shared = !_shared);
                            _scheduleDraft();
                          },
                    child: Text(_shared ? 'Make private' : 'Share with Circle'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _error ??
                          [
                            '$_words ${_words == 1 ? 'word' : 'words'}',
                            if (_draftSaved) 'Draft saved',
                          ].join(' · '),
                      style: TextStyle(
                        color: _error == null
                            ? colors.textSecondary
                            : journalMoodColor(context, 'Stressed'),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _moodOption(BuildContext context, String mood) {
    final colors = context.vivordoColors;
    final color = journalMoodColor(context, mood);
    final selected = _mood == mood;
    return Semantics(
      button: true,
      selected: selected,
      label: mood,
      child: ExcludeSemantics(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _mood = mood);
            _scheduleDraft();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: selected ? color.withValues(alpha: .14) : null,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: selected ? 18 : 14,
                  height: selected ? 18 : 14,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  mood,
                  style: TextStyle(
                    color: selected ? color : colors.textSecondary,
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
