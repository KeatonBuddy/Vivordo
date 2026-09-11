import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  late Future<List<Map<String, dynamic>>> _users = _load();
  final Set<String> _busy = {};

  Future<List<Map<String, dynamic>>> _load() async {
    final result = await FirebaseFunctions.instance
        .httpsCallable('listBlockedCircleUsers')
        .call<Map<String, dynamic>>();
    return (result.data['users'] as List)
        .map((user) => Map<String, dynamic>.from(user as Map))
        .toList();
  }

  Future<void> _unblock(Map<String, dynamic> user) async {
    final id = user['userId'] as String;
    if (_busy.contains(id)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Unblock ${user['username']}?'),
        content: const Text(
          'Your friendship will not be restored automatically. You can send a new friend request unless they have also blocked you.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Unblock'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy.add(id));
    try {
      await FirebaseFunctions.instance
          .httpsCallable('unblockCircleUser')
          .call<void>({'userId': id});
      if (!mounted) return;
      setState(() => _users = _load());
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('User unblocked.')));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not unblock user. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Blocked Users')),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _users,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Could not load blocked users.'),
                TextButton(
                  onPressed: () => setState(() => _users = _load()),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }
        final users = snapshot.data ?? [];
        if (users.isEmpty) {
          return const Center(child: Text('You haven’t blocked anyone.'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: users.length,
          separatorBuilder: (_, _) => const Divider(),
          itemBuilder: (context, index) {
            final user = users[index];
            return ListTile(
              leading: const Icon(Icons.block),
              title: Text(user['username'] as String),
              trailing: TextButton(
                onPressed: _busy.contains(user['userId'])
                    ? null
                    : () => _unblock(user),
                child: Text(
                  _busy.contains(user['userId']) ? 'Unblocking…' : 'Unblock',
                ),
              ),
            );
          },
        );
      },
    ),
  );
}
