import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';

import '../src/services/achievement_service.dart';
import '../src/services/calendar_service.dart';
import '../src/services/journal_lock_service.dart';
import '../src/services/metrics_service.dart';
import '../src/services/outlook_calendar_service.dart';
import '../src/utils/journal_summary.dart';
import '../widgets/apple_ui.dart';
import '../widgets/journal_entry_sheet.dart';

const _purple = Color(0xFF5B4CF4);
const _muted = Color(0xFF7F8098);
const _red = Color(0xFFFF3D4F);

JournalItem _itemFrom(String id, Map<String, dynamic> data) => JournalItem(
  id: id,
  text: data['text'] as String? ?? '',
  date: (data['entryDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
  title: data['title'] as String?,
  mood: data['mood'] as String?,
  shared: data['shareToCircle'] as bool? ?? false,
);

class JournalScreen extends StatefulWidget {
  const JournalScreen({super.key});

  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  final _search = TextEditingController();
  Stream<QuerySnapshot<Map<String, dynamic>>>? _stream;
  late DateTime _month;
  DateTime? _selectedDay;
  bool _searching = false;
  List<String> _prompts = journalPrompts(DateTime.now(), const []);
  int _promptIndex = 0;
  bool _accessChecked = false;
  bool _accessGranted = false;
  bool _journalLocked = false;
  bool _authenticating = false;

  CollectionReference<Map<String, dynamic>>? get _entries {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('journal_entries');
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    // ponytail: the newest 500 entries feed the mood strip, streak and
    // search; page older months from Firestore if journals grow past that.
    _stream = _entries
        ?.orderBy('entryDate', descending: true)
        .limit(500)
        .snapshots();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkJournalAccess());
    _loadPrompts();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  /// Today's finished events become prompts ("How did Standup go?").
  Future<void> _loadPrompts() async {
    final now = DateTime.now();
    final finished = <({String title, DateTime end})>[];
    try {
      final google = await CalendarService.getEventsBetween(
        _today,
        now,
      ).timeout(const Duration(seconds: 6));
      for (final e in google) {
        final end = e.end?.dateTime?.toLocal();
        if (e.status == 'cancelled' || e.start?.dateTime == null) continue;
        if (end != null) finished.add((title: e.summary ?? '', end: end));
      }
    } catch (_) {}
    try {
      final outlook = await OutlookCalendarService.getEventsBetween(
        _today,
        now,
      ).timeout(const Duration(seconds: 6));
      for (final e in outlook) {
        if (!e.isAllDay) finished.add((title: e.subject, end: e.end.toLocal()));
      }
    } catch (_) {}
    if (!mounted || finished.isEmpty) return;
    setState(() {
      _prompts = journalPrompts(now, finished);
      _promptIndex = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_accessChecked || !_accessGranted) return _buildAccessGate();
    final stream = _stream;
    return Scaffold(
      backgroundColor: context.vivordoColors.page,
      body: SafeArea(
        bottom: false,
        child: stream == null
            ? const Center(child: Text('Sign in to use your journal.'))
            : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: stream,
                builder: (context, snapshot) {
                  final items = [
                    for (final d in snapshot.data?.docs ?? const [])
                      _itemFrom(d.id, d.data()),
                  ];
                  final loading =
                      snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData;
                  return ListView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 48),
                    children: [
                      _buildHeader(items),
                      const SizedBox(height: 18),
                      if (!_searching) ...[
                        _buildMonth(items),
                        const SizedBox(height: 14),
                        _buildPromptCard(),
                        const SizedBox(height: 24),
                      ],
                      if (snapshot.hasError)
                        const _Empty(
                          title: 'Couldn’t load your entries',
                          body: 'Check your connection, then reopen Journal.',
                        )
                      else if (loading)
                        const Padding(
                          padding: EdgeInsets.all(34),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else
                        ..._buildList(items),
                    ],
                  );
                },
              ),
      ),
    );
  }

  Widget _buildHeader(List<JournalItem> items) {
    final colors = context.vivordoColors;
    final now = DateTime.now();
    final streak = journalStreak(items, now);
    final monthCount = items
        .where((i) => i.date.year == now.year && i.date.month == now.month)
        .length;
    final summary = [
      if (streak > 0) '$streak-day streak',
      if (monthCount > 0)
        '$monthCount ${monthCount == 1 ? 'entry' : 'entries'} in '
            '${DateFormat('MMMM').format(now)}',
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton.filledTonal(
              tooltip: 'Back',
              onPressed: () => Navigator.maybePop(context),
              icon: const Icon(Icons.chevron_left_rounded, size: 30),
              style: IconButton.styleFrom(
                backgroundColor: colors.card,
                foregroundColor: colors.textPrimary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Journal',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 36,
                  height: 1,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            IconButton(
              tooltip: _searching ? 'Close search' : 'Search entries',
              onPressed: () => setState(() {
                _searching = !_searching;
                _search.clear();
              }),
              icon: Icon(
                _searching ? Icons.close_rounded : Icons.search_rounded,
                color: colors.textSecondary,
              ),
            ),
            IconButton(
              tooltip: _journalLocked
                  ? 'Turn off Journal Lock'
                  : 'Lock Journal',
              onPressed: _authenticating ? null : _toggleJournalLock,
              icon: Icon(
                _journalLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
                color: VivordoTheme.brand,
              ),
            ),
          ],
        ),
        if (_searching)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: TextField(
              controller: _search,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                hintText: 'Search your entries',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              summary.isEmpty
                  ? 'A private space to reflect on your day'
                  : summary,
              style: TextStyle(color: colors.textSecondary, fontSize: 14),
            ),
          ),
      ],
    );
  }

  Widget _buildMonth(List<JournalItem> items) {
    final colors = context.vivordoColors;
    final today = _today;
    final moods = moodsByDay(items, _month);
    final isCurrentMonth =
        _month.year == today.year && _month.month == today.month;
    final days = DateUtils.getDaysInMonth(_month.year, _month.month);
    final name = DateFormat(
      _month.year == today.year ? 'MMMM' : 'MMMM y',
    ).format(_month).toUpperCase();
    return _Card(
      padding: const EdgeInsets.fromLTRB(14, 4, 4, 14),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _SectionTitle('$name MOODS')),
              IconButton(
                tooltip: 'Previous month',
                onPressed: () => setState(() {
                  _month = DateTime(_month.year, _month.month - 1);
                }),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              IconButton(
                tooltip: 'Next month',
                onPressed: isCurrentMonth
                    ? null
                    : () => setState(() {
                        _month = DateTime(_month.year, _month.month + 1);
                      }),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: GridView.count(
              crossAxisCount: 10,
              shrinkWrap: true,
              // Without this the grid adds the screen's safe-area inset.
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 5,
              crossAxisSpacing: 5,
              childAspectRatio: 1.15,
              children: [
                for (var d = 1; d <= days; d++)
                  _dayCell(
                    DateTime(_month.year, _month.month, d),
                    moods,
                    today,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Wrap(
              spacing: 14,
              runSpacing: 4,
              children: [
                for (final (mood, label) in const [
                  ('Good', 'Great · Good'),
                  ('Okay', 'Okay · Low'),
                  ('Stressed', 'Stressed'),
                ])
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: journalMoodColor(context, mood),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        label,
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dayCell(DateTime day, Map<int, String?> moods, DateTime today) {
    final colors = context.vivordoColors;
    final hasEntry = moods.containsKey(day.day);
    final mood = moods[day.day];
    final future = day.isAfter(today);
    final selected =
        _selectedDay != null && DateUtils.isSameDay(_selectedDay, day);
    final isToday = DateUtils.isSameDay(day, today);
    final filled = hasEntry && moodTone(mood) != MoodTone.none;
    return Semantics(
      button: !future,
      selected: selected,
      label:
          '${DateFormat('MMMM d').format(day)}, '
          '${hasEntry ? (mood ?? 'entry without a mood') : 'no entry'}',
      child: ExcludeSemantics(
        child: Opacity(
          opacity: future ? .35 : 1,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: future
                ? null
                : () => setState(() => _selectedDay = selected ? null : day),
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: hasEntry ? journalMoodColor(context, mood) : null,
                borderRadius: BorderRadius.circular(8),
                border: selected
                    ? Border.all(color: VivordoTheme.brand, width: 2.5)
                    : isToday
                    ? Border.all(color: VivordoTheme.brand, width: 1.5)
                    : hasEntry
                    ? null
                    : Border.all(color: colors.border),
              ),
              child: Text(
                '${day.day}',
                style: TextStyle(
                  color: filled ? Colors.white : colors.textSecondary,
                  fontSize: 12,
                  fontWeight: hasEntry ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPromptCard() {
    final prompt = _prompts[_promptIndex % _prompts.length];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF5844ED), Color(0xFF3529AD)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            DateTime.now().hour >= 17 ? "TONIGHT'S PROMPT" : "TODAY'S PROMPT",
            style: const TextStyle(
              color: Color(0xFFD9D1FF),
              fontSize: 11,
              letterSpacing: 1.8,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            prompt,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 19,
              height: 1.3,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: () => _write(date: _today, prompt: prompt),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF3529AD),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text(
                  'Write about today',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              OutlinedButton(
                onPressed: () => setState(() => _promptIndex++),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Color(0x88FFFFFF)),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Another prompt'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildList(List<JournalItem> items) {
    final today = _today;
    var shown = searchJournal(items, _searching ? _search.text : '');
    final day = _selectedDay;
    if (!_searching && day != null) {
      shown = shown.where((i) => DateUtils.isSameDay(i.date, day)).toList();
      return [
        Row(
          children: [
            Expanded(
              child: _SectionTitle(
                DateFormat('EEEE, MMM d').format(day).toUpperCase(),
              ),
            ),
            TextButton(
              onPressed: () => setState(() => _selectedDay = null),
              child: const Text('Show all'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (shown.isEmpty)
          const _Empty(
            title: 'No entries for this day',
            body: 'Add one now if you’d like to remember it.',
          )
        else
          _entryGroup(shown),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => _write(date: day),
          icon: const Icon(Icons.add_rounded),
          label: Text(
            DateUtils.isSameDay(day, today)
                ? 'Write about today'
                : 'Add an entry for ${DateFormat('MMM d').format(day)}',
          ),
        ),
      ];
    }
    if (shown.isEmpty) {
      return [
        _searching
            ? const _Empty(title: 'No matches', body: 'Try a different word.')
            : const _Empty(
                title: 'Start your first entry',
                body: 'Your reflections will appear here, grouped by month.',
              ),
      ];
    }
    if (_searching) {
      return [
        _SectionTitle(
          '${shown.length} ${shown.length == 1 ? 'RESULT' : 'RESULTS'}',
        ),
        const SizedBox(height: 8),
        _entryGroup(shown),
      ];
    }
    final months = <DateTime, List<JournalItem>>{};
    for (final item in shown) {
      months
          .putIfAbsent(DateTime(item.date.year, item.date.month), () => [])
          .add(item);
    }
    return [
      for (final month in months.entries) ...[
        _SectionTitle(
          DateFormat(
            month.key.year == today.year ? 'MMMM' : 'MMMM y',
          ).format(month.key).toUpperCase(),
        ),
        const SizedBox(height: 8),
        _entryGroup(month.value),
        const SizedBox(height: 22),
      ],
    ];
  }

  Widget _entryGroup(List<JournalItem> items) {
    final colors = context.vivordoColors;
    return _Card(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Column(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) Divider(height: 1, indent: 38, color: colors.border),
              _EntryRow(item: items[i], onTap: () => _open(items[i])),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _write({required DateTime date, String? prompt}) async {
    final entries = _entries;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (entries == null || uid == null) return;
    final saved = await showJournalEntrySheet(
      context,
      date: date,
      prompt: prompt,
      draftKey: 'journal_draft_${uid}_${DateFormat('yyyy-MM-dd').format(date)}',
      onSave: (draft) => _create(entries, date, draft),
    );
    if (saved == true && mounted) {
      showToast(context, 'Entry saved.', kind: ToastKind.success);
    }
  }

  Future<void> _create(
    CollectionReference<Map<String, dynamic>> entries,
    DateTime day,
    JournalDraft draft,
  ) async {
    final now = DateTime.now();
    final entryDate = DateTime(
      day.year,
      day.month,
      day.day,
      now.hour,
      now.minute,
    );
    final entryDocument = entries.doc();
    final batch = FirebaseFirestore.instance.batch();
    batch.set(entryDocument, {
      'text': draft.text,
      'title': journalTitleFrom(draft.text),
      'mood': draft.mood,
      'shareToCircle': draft.shared,
      'entryDate': Timestamp.fromDate(entryDate),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (draft.shared) {
      batch.set(_circleEntry(entryDocument.id), {
        ..._circleFields(draft.text, draft.mood, entryDate),
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    // The entry is saved, so the sheet can close now. The follow-ups run in
    // the background: an achievement reconciliation takes seconds, and a
    // failure here must not make the entry look unsaved (a retry would save
    // it twice).
    unawaited(
      MetricsService.saveMoodCheckIn(
        draft.mood,
        occurredAt: entryDate,
        source: 'journal',
      ).catchError((Object error) {
        debugPrint('Could not record the journal mood check-in: $error');
      }),
    );
    unawaited(_refreshStoryKeeperProgress());
  }

  /// Saves an edit of [old]. The first save already recorded its mood
  /// check-in, and check-ins only append, so an edit records none.
  Future<void> _update(
    JournalItem old, {
    required String text,
    required bool shared,
    String? mood,
  }) async {
    final entries = _entries;
    if (entries == null) throw StateError('Sign in to edit this entry.');
    final batch = FirebaseFirestore.instance.batch();
    batch.update(entries.doc(old.id), {
      'text': text,
      'title': journalTitleFrom(text),
      'mood': ?mood,
      'moodEmoji': FieldValue.delete(),
      'shareToCircle': shared,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    final circle = _circleEntry(old.id);
    if (shared) {
      batch.set(circle, {
        ..._circleFields(text, mood ?? old.mood, old.date),
        if (!old.shared) 'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } else if (old.shared) {
      batch.delete(circle);
    }
    await batch.commit();
  }

  DocumentReference<Map<String, dynamic>> _circleEntry(String id) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .collection('circle_activity')
          .doc(id);

  Map<String, dynamic> _circleFields(
    String text,
    String? mood,
    DateTime date,
  ) => {
    'name': 'Journal Entry',
    'kind': 'journal',
    'summary': text,
    'mood': mood,
    'minutes': 0,
    'day': Timestamp.fromDate(date),
  };

  Future<void> _open(JournalItem item) async {
    final entries = _entries;
    if (entries == null) return;
    final reference = entries.doc(item.id);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _JournalEntryDetailScreen(
          reference: reference,
          onEdit: (current, draft) => _update(
            current,
            text: draft.text,
            mood: draft.mood,
            shared: draft.shared,
          ),
          onShare: (current, shared) =>
              _update(current, text: current.text, shared: shared),
          onDelete: () => _deleteEntry(reference),
        ),
      ),
    );
  }

  Widget _buildAccessGate() => Scaffold(
    backgroundColor: context.vivordoColors.page,
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton.filledTonal(
                onPressed: () => Navigator.maybePop(context),
                icon: const Icon(Icons.chevron_left_rounded, size: 30),
              ),
            ),
            const Spacer(),
            Container(
              width: 86,
              height: 86,
              decoration: BoxDecoration(
                color: context.vivordoColors.card,
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(Icons.lock_rounded, color: _purple, size: 42),
            ),
            const SizedBox(height: 22),
            Text(
              _accessChecked ? 'Journal Locked' : 'Opening Journal…',
              style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              _accessChecked
                  ? 'Use Face ID, Touch ID, or your device passcode to view your entries.'
                  : 'Checking your privacy settings.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted, height: 1.4),
            ),
            const SizedBox(height: 24),
            if (!_accessChecked || _authenticating)
              const CircularProgressIndicator(color: _purple)
            else
              FilledButton.icon(
                onPressed: _unlockJournal,
                style: FilledButton.styleFrom(
                  backgroundColor: _purple,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: const Icon(Icons.lock_open_rounded),
                label: const Text(
                  'Unlock Journal',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            const Spacer(flex: 2),
          ],
        ),
      ),
    ),
  );

  Future<void> _checkJournalAccess() async {
    final locked = await JournalLockService.isEnabled();
    if (!mounted) return;
    if (!locked) {
      setState(() {
        _journalLocked = false;
        _accessGranted = true;
        _accessChecked = true;
      });
      return;
    }
    setState(() {
      _journalLocked = true;
      _accessChecked = true;
    });
    await _unlockJournal();
  }

  Future<void> _unlockJournal() async {
    if (_authenticating) return;
    setState(() => _authenticating = true);
    final authenticated = await JournalLockService.authenticate(
      reason: 'Authenticate to open your Vivordo journal.',
    );
    if (!mounted) return;
    setState(() {
      _authenticating = false;
      _accessGranted = authenticated;
    });
  }

  Future<void> _toggleJournalLock() async {
    final enabling = !_journalLocked;
    if (enabling && !await JournalLockService.hasSeenIntroduction()) {
      if (!mounted) return;
      final continueSetup = await _showJournalLockIntroduction();
      if (!continueSetup || !mounted) return;
    }
    setState(() => _authenticating = true);
    final authenticated = await JournalLockService.authenticate(
      reason: enabling
          ? 'Authenticate to enable Journal Lock.'
          : 'Authenticate to turn off Journal Lock.',
    );
    if (!mounted) return;
    if (!authenticated) {
      setState(() => _authenticating = false);
      return;
    }
    try {
      await JournalLockService.setEnabled(enabling);
      if (enabling) await JournalLockService.markIntroductionSeen();
      if (!mounted) return;
      setState(() {
        _journalLocked = enabling;
        _authenticating = false;
      });
      showToast(
        context,
        enabling ? 'Journal Lock on.' : 'Journal Lock off.',
        kind: ToastKind.success,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _authenticating = false);
      debugPrint('Update Journal Lock failed: $error');
      showToast(
        context,
        "Couldn't update Journal Lock. Try again.",
        kind: ToastKind.error,
      );
    }
  }

  Future<bool> _showJournalLockIntroduction() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        icon: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: _purple.withValues(alpha: .10),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(Icons.lock_rounded, color: _purple, size: 32),
        ),
        title: const Text(
          'Protect your journal',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Journal Lock keeps your reflections hidden whenever you open the Journal.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, height: 1.4),
            ),
            SizedBox(height: 18),
            _JournalLockInfoRow(
              icon: Icons.face_rounded,
              text: 'Unlock with Face ID, Touch ID, or your device passcode.',
            ),
            SizedBox(height: 12),
            _JournalLockInfoRow(
              icon: Icons.visibility_off_rounded,
              text:
                  'Your entries stay hidden when authentication is cancelled.',
            ),
            SizedBox(height: 12),
            _JournalLockInfoRow(
              icon: Icons.lock_open_rounded,
              text: 'You can turn Journal Lock off from the lock icon anytime.',
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Not Now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: _purple),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _deleteEntry(
    DocumentReference<Map<String, dynamic>> journalEntry,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Sign in to delete this entry.');
    final circleEntry = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('circle_activity')
        .doc(journalEntry.id);
    final batch = FirebaseFirestore.instance.batch();
    batch.delete(journalEntry);
    batch.delete(circleEntry);
    await batch.commit();
    unawaited(_refreshStoryKeeperProgress());
  }

  Future<void> _refreshStoryKeeperProgress() async {
    try {
      await AchievementService.reconcileStoryKeeper();
    } catch (error) {
      // The journal write has already succeeded. Goals performs the same
      // reconciliation later, so an unavailable network must not make a
      // successful save or deletion look like it failed.
      debugPrint('Could not refresh Story Keeper progress: $error');
    }
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, required this.padding});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: context.vivordoColors.card,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: context.vivordoColors.border),
    ),
    child: child,
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: TextStyle(
      color: context.vivordoColors.textSecondary,
      fontSize: 13,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.3,
    ),
  );
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.item, required this.onTap});

  final JournalItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return Semantics(
      button: true,
      label:
          'Open ${item.displayTitle}, '
          '${item.shared ? 'shared with your Circle' : 'private'}',
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    color: journalMoodColor(context, item.mood),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          DateFormat('EEE d · h:mm a').format(item.date),
                          ?item.mood,
                        ].join(' · '),
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  item.shared ? Icons.groups_rounded : Icons.lock_outline,
                  size: 17,
                  color: colors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _JournalEntryDetailScreen extends StatefulWidget {
  const _JournalEntryDetailScreen({
    required this.reference,
    required this.onEdit,
    required this.onShare,
    required this.onDelete,
  });

  final DocumentReference<Map<String, dynamic>> reference;
  final Future<void> Function(JournalItem current, JournalDraft draft) onEdit;
  final Future<void> Function(JournalItem current, bool shared) onShare;
  final Future<void> Function() onDelete;

  @override
  State<_JournalEntryDetailScreen> createState() =>
      _JournalEntryDetailScreenState();
}

class _JournalEntryDetailScreenState extends State<_JournalEntryDetailScreen> {
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _stream = widget
      .reference
      .snapshots();
  bool _confirmingDelete = false;
  bool _deleting = false;
  bool _sharing = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final item = data == null ? null : _itemFrom(widget.reference.id, data);
        return Scaffold(
          backgroundColor: colors.page,
          appBar: AppBar(
            backgroundColor: colors.page,
            surfaceTintColor: Colors.transparent,
            title: const Text(
              'Journal entry',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            actions: [
              if (item != null && !_deleting)
                TextButton(
                  onPressed: () => _edit(item),
                  child: const Text(
                    'Edit',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
            ],
          ),
          body: SafeArea(
            child: item == null
                ? Center(
                    child: snapshot.hasData
                        ? Text(
                            'This entry was deleted.',
                            style: TextStyle(color: colors.textSecondary),
                          )
                        : const CircularProgressIndicator(),
                  )
                : _body(context, item),
          ),
        );
      },
    );
  }

  Widget _body(BuildContext context, JournalItem item) {
    final colors = context.vivordoColors;
    final moodColor = journalMoodColor(context, item.mood);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
      children: [
        _Card(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                DateFormat('EEEE, MMMM d · h:mm a').format(item.date),
                style: TextStyle(color: colors.textSecondary, fontSize: 13),
              ),
              if (item.mood != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: moodColor.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: moodColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        item.mood!,
                        style: TextStyle(
                          color: moodColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              // No heading: titles are the entry's own first line, so the
              // text alone reads better than repeating it.
              const SizedBox(height: 16),
              SelectableText(
                item.text,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 17,
                  height: 1.55,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Card(
          padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
          child: Row(
            children: [
              Icon(
                item.shared ? Icons.groups_rounded : Icons.lock_outline,
                color: colors.textSecondary,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.shared
                          ? 'Shared with your Circle'
                          : 'Private to you',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      item.shared
                          ? 'Your Circle can see this entry.'
                          : 'Only you can see this entry.',
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              AppSwitch(
                value: item.shared,
                onChanged: _sharing ? null : (shared) => _share(item, shared),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: _deleting ? null : _delete,
          style: OutlinedButton.styleFrom(
            foregroundColor: _red,
            side: BorderSide(
              color: _confirmingDelete ? _red : _red.withValues(alpha: .45),
            ),
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
          ),
          icon: _deleting
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(color: _red, strokeWidth: 2),
                )
              : const Icon(Icons.delete_outline_rounded),
          label: Text(
            _deleting
                ? 'Deleting…'
                : _confirmingDelete
                ? 'Tap again to delete permanently'
                : 'Delete entry',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }

  Future<void> _edit(JournalItem item) async {
    final saved = await showJournalEntrySheet(
      context,
      date: item.date,
      editing: item,
      onSave: (draft) => widget.onEdit(item, draft),
    );
    if (saved == true && mounted) {
      showToast(context, 'Entry updated.', kind: ToastKind.success);
    }
  }

  Future<void> _share(JournalItem item, bool shared) async {
    setState(() => _sharing = true);
    try {
      await widget.onShare(item, shared);
    } catch (error) {
      debugPrint('Change journal sharing failed: $error');
      if (mounted) {
        showToast(
          context,
          'Couldn’t change sharing. Try again.',
          kind: ToastKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _delete() async {
    if (!_confirmingDelete) {
      setState(() => _confirmingDelete = true);
      return;
    }
    setState(() => _deleting = true);
    try {
      await widget.onDelete();
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _confirmingDelete = false;
      });
      debugPrint('Delete journal entry failed: $error');
      showToast(
        context,
        "Couldn't delete the entry. Try again.",
        kind: ToastKind.error,
      );
    }
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return _Card(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      child: Column(
        children: [
          Icon(
            Icons.auto_stories_outlined,
            color: colors.textSecondary,
            size: 32,
          ),
          const SizedBox(height: 9),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _JournalLockInfoRow extends StatelessWidget {
  const _JournalLockInfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: _purple, size: 20),
      const SizedBox(width: 11),
      Expanded(
        child: Text(text, style: const TextStyle(fontSize: 13, height: 1.35)),
      ),
    ],
  );
}
