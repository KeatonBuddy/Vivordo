import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';

/// Deletes a remembered fact and the summary of the chat it came from, as
/// when Vivordo AI forgets one itself, or the fact would come back through
/// that summary.
WriteBatch forgetFactBatch(
  FirebaseFirestore db,
  DocumentSnapshot<Map<String, dynamic>> fact,
) {
  final batch = db.batch()..delete(fact.reference);
  final chat = fact.data()?['conversationId'];
  final user = fact.reference.parent.parent;
  if (chat is String && chat.isNotEmpty && user != null) {
    batch.delete(user.collection('conversations').doc(chat));
  }
  return batch;
}

/// What Vivordo AI remembers: the facts it saved from chats
/// (users/{uid}/memory) and its summaries of recent chats
/// (users/{uid}/conversations). Both are sent with every message, so
/// removing one here is what makes Vivordo AI forget it.
class AssistantMemoryScreen extends StatelessWidget {
  const AssistantMemoryScreen({super.key});

  static const _sections = [
    ('stressor', 'STRESSORS'),
    ('helps', 'WHAT HELPS'),
    ('pattern', 'PATTERNS'),
    ('context', 'ABOUT YOU'),
    ('preference', 'HOW YOU LIKE TO TALK'),
  ];

  DocumentReference<Map<String, dynamic>> get _user => FirebaseFirestore
      .instance
      .collection('users')
      .doc(FirebaseAuth.instance.currentUser?.uid ?? '_');

  Future<void> _forgetFact(
    BuildContext context,
    DocumentSnapshot<Map<String, dynamic>> fact,
  ) => _commit(context, forgetFactBatch(FirebaseFirestore.instance, fact));

  Future<void> _forgetEverything(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Forget everything?'),
        content: const Text(
          'Vivordo AI forgets every fact and chat summary below. Your chat '
          'messages and health data stay.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Forget'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final [facts, chats] = await Future.wait([
      _user.collection('memory').get(),
      _user.collection('conversations').get(),
    ]);
    final batch = FirebaseFirestore.instance.batch();
    // ponytail: one batch, fine under 500 docs (100 facts max plus summaries).
    for (final doc in [...facts.docs, ...chats.docs]) {
      batch.delete(doc.reference);
    }
    if (context.mounted) await _commit(context, batch);
  }

  Future<void> _commit(BuildContext context, WriteBatch batch) async {
    try {
      await batch.commit();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Couldn’t remove that. Try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return Scaffold(
      backgroundColor: colors.page,
      appBar: AppBar(
        backgroundColor: colors.page,
        title: const Text('Vivordo AI'),
      ),
      body: _query(
        'memory',
        (factsSnap) => _query('conversations', (chatsSnap) {
          final facts = factsSnap.docs
              .where((d) => (d.data()['text'] as String? ?? '').trim() != '')
              .toList();
          final chats = chatsSnap.docs
              .where((d) => (d.data()['summary'] as String? ?? '').trim() != '')
              .toList();
          String kindOf(DocumentSnapshot<Map<String, dynamic>> d) {
            final kind = d.data()?['kind'];
            return _sections.any((s) => s.$1 == kind)
                ? kind as String
                : 'context';
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: [
              Text(
                'What Vivordo AI knows',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Built from your chats. Remove anything and Vivordo AI '
                'forgets it.',
                style: TextStyle(color: colors.textSecondary, height: 1.4),
              ),
              for (final (kind, heading) in _sections)
                if (facts.any((f) => kindOf(f) == kind))
                  _Section(
                    heading: heading,
                    rows: [
                      for (final fact in facts.where((f) => kindOf(f) == kind))
                        _Row(
                          text: fact.data()['text'] as String,
                          onForget: () => _forgetFact(context, fact),
                        ),
                    ],
                  ),
              if (chats.isNotEmpty)
                _Section(
                  heading: 'RECENT CHATS',
                  rows: [
                    for (final chat in chats)
                      _Row(
                        label: _day(chat.data()['updatedAt']),
                        text: chat.data()['summary'] as String,
                        onForget: () => _commit(
                          context,
                          FirebaseFirestore.instance.batch()
                            ..delete(chat.reference),
                        ),
                      ),
                  ],
                ),
              if (facts.isEmpty && chats.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 32),
                  child: Text(
                    'Nothing yet. As you chat, Vivordo AI saves short notes '
                    'here, like what stresses you and what helps.',
                    style: TextStyle(color: colors.textSecondary, height: 1.4),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Center(
                    child: TextButton(
                      onPressed: () => _forgetEverything(context),
                      child: const Text('Forget everything'),
                    ),
                  ),
                ),
            ],
          );
        }),
      ),
    );
  }

  /// One of the user's collections, newest first, live.
  Widget _query(
    String collection,
    Widget Function(QuerySnapshot<Map<String, dynamic>>) builder,
  ) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: _user
        .collection(collection)
        .orderBy('updatedAt', descending: true)
        .snapshots(),
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Center(child: Text('Couldn’t load memory.'));
      }
      final data = snapshot.data;
      return data == null
          ? const Center(child: CircularProgressIndicator())
          : builder(data);
    },
  );

  static String _day(Object? at) =>
      at is Timestamp ? DateFormat('MMM d').format(at.toDate()) : 'Earlier';
}

class _Section extends StatelessWidget {
  const _Section({required this.heading, required this.rows});

  final String heading;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            heading,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.border),
            ),
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: colors.border),
                  rows[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.text, required this.onForget, this.label});

  final String text;
  final String? label;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Padding(
        padding: const EdgeInsets.only(left: 16),
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (label != null)
                      Text(
                        label!,
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    Text(
                      text,
                      style: TextStyle(color: colors.textPrimary, height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: 'Forget',
              icon: Icon(Icons.close_rounded, color: colors.textSecondary),
              onPressed: onForget,
            ),
          ],
        ),
      ),
    );
  }
}
