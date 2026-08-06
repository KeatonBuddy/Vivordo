import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

const _purple = Color(0xFF6B5CE7);
const _background = Color(0xFFF2F2F7);
const _ink = Color(0xFF17172B);
const _muted = Color(0xFF85859B);

class JournalScreen extends StatefulWidget {
  const JournalScreen({super.key});

  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  CollectionReference<Map<String, dynamic>>? get _entries {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('journal_entries');
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Journal',
          style: TextStyle(color: _ink, fontWeight: FontWeight.w800),
        ),
      ),
      body: entries == null
          ? const Center(child: Text('Sign in to use your journal.'))
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: entries
                  .orderBy('entryDate', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: _purple),
                  );
                }
                final documents = snapshot.data?.docs ?? const [];
                return ListView(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 130),
                  children: [
                    _JournalPrompt(onTap: _writeEntry),
                    const SizedBox(height: 26),
                    const Text(
                      'RECENT ENTRIES',
                      style: TextStyle(
                        color: _muted,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.3,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (documents.isEmpty)
                      const _EmptyJournal()
                    else
                      for (final document in documents) ...[
                        _JournalEntryCard(document: document),
                        const SizedBox(height: 10),
                      ],
                  ],
                );
              },
            ),
      floatingActionButton: entries == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _writeEntry,
              backgroundColor: _purple,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.edit_rounded),
              label: const Text(
                'New Entry',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
    );
  }

  Future<void> _writeEntry() async {
    final entries = _entries;
    if (entries == null) return;
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _JournalEditorSheet(),
    );
    if (text == null || !mounted) return;
    try {
      final now = DateTime.now();
      await entries.add({
        'text': text,
        'entryDate': Timestamp.fromDate(now),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save journal entry: $error')),
      );
    }
  }
}

class _JournalEditorSheet extends StatefulWidget {
  const _JournalEditorSheet();

  @override
  State<_JournalEditorSheet> createState() => _JournalEditorSheetState();
}

class _JournalEditorSheetState extends State<_JournalEditorSheet> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      4,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 20,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          DateFormat('EEEE, MMMM d').format(DateTime.now()),
          style: const TextStyle(
            color: _ink,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        const Text('What is on your mind?', style: TextStyle(color: _muted)),
        const SizedBox(height: 14),
        TextField(
          controller: _controller,
          autofocus: true,
          minLines: 7,
          maxLines: 12,
          maxLength: 5000,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: 'Write about your day…',
            filled: true,
            fillColor: const Color(0xFFF7F7FA),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
          ),
          onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: () {
            final value = _controller.text.trim();
            if (value.isNotEmpty) Navigator.pop(context, value);
          },
          style: FilledButton.styleFrom(
            backgroundColor: _purple,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          icon: const Icon(Icons.bookmark_add_rounded),
          label: const Text(
            'Save Entry',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    ),
  );
}

class _JournalPrompt extends StatelessWidget {
  const _JournalPrompt({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(22),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: const Color(0xFFF2EDFF),
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Icon(Icons.menu_book_rounded, color: _purple),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Reflect on today',
                    style: TextStyle(
                      color: _ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Capture a thought, feeling, or meaningful moment.',
                    style: TextStyle(color: _muted, height: 1.3),
                  ),
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

class _JournalEntryCard extends StatelessWidget {
  const _JournalEntryCard({required this.document});

  final QueryDocumentSnapshot<Map<String, dynamic>> document;

  @override
  Widget build(BuildContext context) {
    final data = document.data();
    final date = (data['entryDate'] as Timestamp?)?.toDate() ?? DateTime.now();
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withValues(alpha: .06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            DateFormat('EEEE, MMMM d · h:mm a').format(date),
            style: const TextStyle(
              color: _purple,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            data['text'] as String? ?? '',
            style: const TextStyle(color: _ink, fontSize: 15, height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _EmptyJournal extends StatelessWidget {
  const _EmptyJournal();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
    ),
    child: const Column(
      children: [
        Icon(Icons.auto_stories_outlined, color: _muted, size: 34),
        SizedBox(height: 10),
        Text(
          'Your journal is ready',
          style: TextStyle(color: _ink, fontWeight: FontWeight.w800),
        ),
        SizedBox(height: 4),
        Text(
          'Your saved reflections will appear here.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _muted),
        ),
      ],
    ),
  );
}
