import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';
import 'package:intl/intl.dart';

import '../src/services/metrics_service.dart';
import '../src/services/journal_lock_service.dart';

const _purple = Color(0xFF5B4CF4);
const _muted = Color(0xFF7F8098);
const _green = Color(0xFF05A956);
const _orange = Color(0xFFFF7A00);
const _red = Color(0xFFFF3D4F);

class _MoodChoice {
  const _MoodChoice(this.label, this.emoji, this.color);

  final String label;
  final String emoji;
  final Color color;
}

const _moods = <_MoodChoice>[
  _MoodChoice('Great', '☺', _green),
  _MoodChoice('Good', '🙂', _green),
  _MoodChoice('Okay', '😐', _orange),
  _MoodChoice('Low', '☹', _orange),
  _MoodChoice('Stressed', '😣', _red),
];

class JournalScreen extends StatefulWidget {
  const JournalScreen({super.key});

  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  final _entryController = TextEditingController();
  late DateTime _selectedDate;
  int _weekOffset = 0;
  int _selectedMood = 1;
  bool _shareToCircle = false;
  bool _showAll = false;
  bool _saving = false;
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
    _selectedDate = DateTime(now.year, now.month, now.day);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkJournalAccess());
  }

  @override
  void dispose() {
    _entryController.dispose();
    super.dispose();
  }

  DateTime get _weekStart {
    final today = DateTime.now().add(Duration(days: _weekOffset * 7));
    final day = DateTime(today.year, today.month, today.day);
    return day.subtract(Duration(days: day.weekday - 1));
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    if (!_accessChecked || !_accessGranted) return _buildAccessGate();
    final entries = _entries;
    return Scaffold(
      backgroundColor: context.vivordoColors.page,
      body: SafeArea(
        bottom: false,
        child: entries == null
            ? const Center(child: Text('Sign in to use your journal.'))
            : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: entries
                    .orderBy('entryDate', descending: true)
                    .snapshots(),
                builder: (context, snapshot) => ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 48),
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 22),
                    _buildWeekPicker(),
                    const SizedBox(height: 24),
                    const _SectionTitle('TODAY'),
                    const SizedBox(height: 10),
                    _buildComposer(entries),
                    const SizedBox(height: 24),
                    _buildRecentHeader(),
                    const SizedBox(height: 10),
                    if (snapshot.connectionState == ConnectionState.waiting &&
                        !snapshot.hasData)
                      const Padding(
                        padding: EdgeInsets.all(34),
                        child: Center(
                          child: CircularProgressIndicator(color: _purple),
                        ),
                      )
                    else
                      _buildEntries(snapshot.data?.docs ?? const []),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildHeader() => Row(
    children: [
      IconButton.filledTonal(
        tooltip: 'Back',
        onPressed: () => Navigator.maybePop(context),
        icon: const Icon(Icons.chevron_left_rounded, size: 30),
        style: IconButton.styleFrom(
          backgroundColor: context.vivordoColors.card,
          foregroundColor: context.vivordoColors.textPrimary,
        ),
      ),
      const SizedBox(width: 8),
      const Expanded(
        child: Text(
          'Journal',
          style: TextStyle(
            fontSize: 36,
            height: 1,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          color: context.vivordoColors.card,
          borderRadius: BorderRadius.circular(17),
          boxShadow: const [
            BoxShadow(
              color: Color(0x12000000),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: IconButton(
          tooltip: _journalLocked ? 'Turn off Journal Lock' : 'Lock Journal',
          onPressed: _authenticating ? null : _toggleJournalLock,
          icon: Icon(
            _journalLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
            color: _purple,
          ),
        ),
      ),
    ],
  );

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabling ? 'Journal Lock enabled.' : 'Journal Lock disabled.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _authenticating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update Journal Lock: $error')),
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

  Widget _buildWeekPicker() {
    final days = List.generate(
      7,
      (index) => _weekStart.add(Duration(days: index)),
    );
    return _Card(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 15),
      child: Row(
        children: [
          IconButton(
            onPressed: () => setState(() => _weekOffset--),
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          for (final day in days)
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _selectedDate = day),
                child: Column(
                  children: [
                    Text(
                      DateFormat('E').format(day).characters.first,
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _sameDay(day, _selectedDate)
                            ? _purple
                            : Colors.transparent,
                      ),
                      child: Text(
                        '${day.day}',
                        style: TextStyle(
                          color: _sameDay(day, _selectedDate)
                              ? Colors.white
                              : context.vivordoColors.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          IconButton(
            onPressed: () => setState(() => _weekOffset++),
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildComposer(
    CollectionReference<Map<String, dynamic>> entries,
  ) => _Card(
    padding: const EdgeInsets.all(16),
    child: Column(
      children: [
        Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFFF0EEFF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.menu_book_rounded, color: _purple),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'How are you feeling?',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    DateFormat('EEEE, MMMM d').format(_selectedDate),
                    style: const TextStyle(color: _muted, fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: List.generate(_moods.length, (index) {
            final mood = _moods[index];
            final selected = index == _selectedMood;
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _selectedMood = index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: selected
                        ? mood.color.withValues(alpha: .10)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      Text(
                        mood.emoji,
                        style: TextStyle(fontSize: 27, color: mood.color),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        mood.label,
                        style: TextStyle(
                          color: selected ? mood.color : _muted,
                          fontSize: 12,
                          fontWeight: selected
                              ? FontWeight.w800
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _entryController,
          minLines: 5,
          maxLines: 9,
          maxLength: 5000,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            counterText: '',
            hintText: 'Start writing…',
            hintStyle: const TextStyle(color: Color(0xFFA1A2B8)),
            filled: true,
            fillColor: context.vivordoColors.cardMuted,
            contentPadding: const EdgeInsets.all(15),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
          ),
          onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _saving ? null : () => _saveEntry(entries),
          style: FilledButton.styleFrom(
            backgroundColor: _purple,
            disabledBackgroundColor: _purple.withValues(alpha: .45),
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
          ),
          icon: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Icon(Icons.edit_rounded),
          label: Text(
            _saving ? 'Saving…' : "Write Today's Entry",
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(height: 9),
        OutlinedButton.icon(
          onPressed: () => setState(() => _shareToCircle = !_shareToCircle),
          style: OutlinedButton.styleFrom(
            foregroundColor: _purple,
            side: BorderSide(
              color: _shareToCircle ? _purple : _purple.withValues(alpha: .5),
            ),
            backgroundColor: _shareToCircle
                ? _purple.withValues(alpha: .07)
                : Colors.transparent,
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
          ),
          icon: Icon(
            _shareToCircle ? Icons.check_circle_rounded : Icons.groups_rounded,
          ),
          label: Text(
            _shareToCircle ? 'Sharing to Circle' : 'Share to Circle',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(height: 9),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_rounded, color: _muted, size: 14),
            const SizedBox(width: 5),
            Text(
              _shareToCircle
                  ? 'Your Circle can see this entry'
                  : 'Private to you',
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _buildRecentHeader() => Row(
    children: [
      const Expanded(child: _SectionTitle('RECENT ENTRIES')),
      TextButton(
        onPressed: () => setState(() => _showAll = !_showAll),
        child: Text(_showAll ? 'Show Less' : 'View All'),
      ),
    ],
  );

  Widget _buildEntries(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> documents,
  ) {
    final entriesForSelectedDay = documents
        .where((document) {
          final timestamp = document.data()['entryDate'] as Timestamp?;
          return timestamp != null &&
              _sameDay(timestamp.toDate(), _selectedDate);
        })
        .toList(growable: false);
    final visibleEntries = _showAll ? documents : entriesForSelectedDay.take(3);
    if (visibleEntries.isEmpty) {
      return _EmptyJournal(date: _selectedDate, showingAll: _showAll);
    }
    return Column(
      children: [
        for (final document in visibleEntries) ...[
          _JournalEntryCard(
            document: document,
            onTap: () => _openEntry(document),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Future<void> _openEntry(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _JournalEntryDetailScreen(
          document: document,
          onDelete: () => _deleteEntry(document.reference),
        ),
      ),
    );
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
  }

  Future<void> _saveEntry(
    CollectionReference<Map<String, dynamic>> entries,
  ) async {
    final text = _entryController.text.trim();
    if (text.isEmpty || _saving) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final entryDate = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        now.hour,
        now.minute,
      );
      final mood = _moods[_selectedMood];
      final entryDocument = entries.doc();
      final entryData = <String, dynamic>{
        'text': text,
        'title': _titleFrom(text),
        'mood': mood.label,
        'moodEmoji': mood.emoji,
        'shareToCircle': _shareToCircle,
        'entryDate': Timestamp.fromDate(entryDate),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      final batch = FirebaseFirestore.instance.batch();
      batch.set(entryDocument, entryData);
      if (_shareToCircle) {
        final user = FirebaseAuth.instance.currentUser!;
        final circleEntry = FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('circle_activity')
            .doc(entryDocument.id);
        batch.set(circleEntry, {
          'name': 'Journal Entry',
          'kind': 'journal',
          'summary': text,
          'mood': mood.label,
          'minutes': 0,
          'day': Timestamp.fromDate(entryDate),
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
      await MetricsService.saveMoodCheckIn(
        mood.label,
        occurredAt: entryDate,
        source: 'journal',
      );
      _entryController.clear();
      if (mounted) {
        setState(() {
          _shareToCircle = false;
          _saving = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Journal entry saved.')));
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save journal entry: $error')),
      );
    }
  }

  String _titleFrom(String text) {
    final firstLine = text.split('\n').first.trim();
    if (firstLine.length <= 42) return firstLine;
    return '${firstLine.substring(0, 39).trimRight()}…';
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
      boxShadow: const [
        BoxShadow(
          color: Color(0x0B000000),
          blurRadius: 20,
          offset: Offset(0, 8),
        ),
      ],
    ),
    child: child,
  );
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: const TextStyle(
      color: _muted,
      fontSize: 13,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.3,
    ),
  );
}

class _JournalEntryCard extends StatelessWidget {
  const _JournalEntryCard({required this.document, required this.onTap});

  final QueryDocumentSnapshot<Map<String, dynamic>> document;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final data = document.data();
    final date = (data['entryDate'] as Timestamp?)?.toDate() ?? DateTime.now();
    final text = data['text'] as String? ?? '';
    final title = data['title'] as String? ?? _fallbackTitle(text);
    final mood = data['mood'] as String?;
    final emoji = data['moodEmoji'] as String? ?? '☺';
    final shared = data['shareToCircle'] as bool? ?? false;
    return Semantics(
      button: true,
      label: 'Open $title',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: _Card(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F0FA),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      DateFormat('MMM').format(date).toUpperCase(),
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text('${date.day}', style: const TextStyle(fontSize: 24)),
                  ],
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _muted, height: 1.3),
                    ),
                    if (mood != null) ...[
                      const SizedBox(height: 7),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _green.withValues(alpha: .09),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(
                          '$emoji  $mood${shared ? ' · Circle' : ''}',
                          style: const TextStyle(
                            color: _green,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: _muted),
            ],
          ),
        ),
      ),
    );
  }

  String _fallbackTitle(String text) {
    final line = text.split('\n').first.trim();
    if (line.isEmpty) return 'Journal entry';
    return line.length > 42 ? '${line.substring(0, 39)}…' : line;
  }
}

class _JournalEntryDetailScreen extends StatefulWidget {
  const _JournalEntryDetailScreen({
    required this.document,
    required this.onDelete,
  });

  final QueryDocumentSnapshot<Map<String, dynamic>> document;
  final Future<void> Function() onDelete;

  @override
  State<_JournalEntryDetailScreen> createState() =>
      _JournalEntryDetailScreenState();
}

class _JournalEntryDetailScreenState extends State<_JournalEntryDetailScreen> {
  bool _confirmingDelete = false;
  bool _deleting = false;

  @override
  Widget build(BuildContext context) {
    final data = widget.document.data();
    final date = (data['entryDate'] as Timestamp?)?.toDate() ?? DateTime.now();
    final text = data['text'] as String? ?? '';
    final title = data['title'] as String? ?? 'Journal Entry';
    final mood = data['mood'] as String?;
    final emoji = data['moodEmoji'] as String? ?? '☺';
    final shared = data['shareToCircle'] as bool? ?? false;
    return Scaffold(
      backgroundColor: context.vivordoColors.page,
      appBar: AppBar(
        backgroundColor: context.vivordoColors.page,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Journal Entry',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
          children: [
            _Card(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0EEFF),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.menu_book_rounded,
                          color: _purple,
                        ),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              DateFormat('EEEE, MMMM d · h:mm a').format(date),
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                if (mood != null)
                                  Text(
                                    '$emoji  $mood',
                                    style: const TextStyle(
                                      color: _green,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                if (mood != null) const SizedBox(width: 12),
                                Icon(
                                  shared
                                      ? Icons.groups_rounded
                                      : Icons.lock_rounded,
                                  color: _muted,
                                  size: 15,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  shared ? 'Shared to Circle' : 'Private',
                                  style: const TextStyle(
                                    color: _muted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    text,
                    style: const TextStyle(fontSize: 16, height: 1.55),
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
                      child: CircularProgressIndicator(
                        color: _red,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.delete_outline_rounded),
              label: Text(
                _deleting
                    ? 'Deleting…'
                    : _confirmingDelete
                    ? 'Tap again to delete permanently'
                    : 'Delete Entry',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete journal entry: $error')),
      );
    }
  }
}

class _EmptyJournal extends StatelessWidget {
  const _EmptyJournal({required this.date, this.showingAll = false});

  final DateTime date;
  final bool showingAll;

  @override
  Widget build(BuildContext context) => _Card(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
    child: Column(
      children: [
        const Icon(Icons.auto_stories_outlined, color: _muted, size: 34),
        const SizedBox(height: 9),
        Text(
          showingAll ? 'No journal entries yet' : 'No entries for this day',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          showingAll
              ? 'Your saved reflections will appear here.'
              : 'Write a reflection for ${DateFormat('MMMM d').format(date)}.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: _muted),
        ),
      ],
    ),
  );
}
