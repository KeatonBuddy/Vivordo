import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/vivordo_theme.dart';
import '../widgets/apple_ui.dart';

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
    final confirmed = await confirmAction(
      context,
      title: 'Unblock ${user['username']}?',
      message:
          'Your friendship won’t be restored automatically. You can send a '
          'new friend request unless they’ve also blocked you.',
      confirmLabel: 'Unblock',
      destructive: false,
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy.add(id));
    try {
      await FirebaseFunctions.instance
          .httpsCallable('unblockCircleUser')
          .call<void>({'userId': id});
      if (!mounted) return;
      setState(() => _users = _load());
      showToast(
        context,
        '${user['username']} unblocked.',
        kind: ToastKind.success,
      );
    } catch (error) {
      debugPrint('Unblock failed: $error');
      if (mounted) {
        showToast(
          context,
          'Couldn’t unblock ${user['username']}. Try again.',
          kind: ToastKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return Scaffold(
      backgroundColor: colors.page,
      appBar: AppBar(
        backgroundColor: colors.page,
        title: const Text('Blocked Users'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _users,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CupertinoActivityIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Couldn’t load blocked users.',
                    style: TextStyle(color: colors.textSecondary),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _users = _load()),
                    child: const Text('Try again'),
                  ),
                ],
              ),
            );
          }
          final users = snapshot.data ?? [];
          if (users.isEmpty) {
            return Center(
              child: Text(
                'You haven’t blocked anyone.',
                style: TextStyle(color: colors.textSecondary),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              AppleFormGroup(
                footer:
                    'Blocked people can’t see your Circle activity or send '
                    'you requests.',
                children: [
                  for (final user in users)
                    AppleFormRow(
                      label: user['username'] as String,
                      leading: _Initials(user['username'] as String),
                      trailing: CupertinoButton(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(44, 32),
                        onPressed: _busy.contains(user['userId'])
                            ? null
                            : () => _unblock(user),
                        child: Text(
                          _busy.contains(user['userId'])
                              ? 'Unblocking…'
                              : 'Unblock',
                          style: TextStyle(
                            fontSize: 15,
                            color: _busy.contains(user['userId'])
                                ? colors.textSecondary
                                : Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Initials extends StatelessWidget {
  const _Initials(this.name);

  final String name;

  @override
  Widget build(BuildContext context) {
    final initials = name
        .split(RegExp(r'[\s._-]+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
    return CircleAvatar(
      radius: 16,
      backgroundColor: VivordoTheme.brand.withValues(alpha: .15),
      child: Text(
        initials,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: VivordoTheme.brand,
        ),
      ),
    );
  }
}
