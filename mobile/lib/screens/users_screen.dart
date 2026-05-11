import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/theme.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  List<dynamic> _users = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final users = await api.getUsers();
      if (mounted) {
        setState(() {
          _users = users;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final admins = _users.where((u) => u['role'] == 'admin').length;
    final workers = _users.where((u) => u['role'] == 'field_worker').length;
    final citizens = _users.where((u) => u['role'] == 'citizen').length;
    final pending = _users.where((u) => u['upgrade_requested'] == true).length;

    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(title: const Text('Users')),
      body: RefreshIndicator(
        onRefresh: _load,
        color: kPrimary,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: kPrimary))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: EdgeInsets.zero,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 1.65,
                    children: [
                      _UserStat('Total Users', '${_users.length}', Icons.people, kPrimary),
                      _UserStat('Pending Pro', '$pending', Icons.workspace_premium, kFair),
                      _UserStat('Field Workers', '$workers', Icons.badge, Colors.blue.shade600),
                      _UserStat('Citizens', '$citizens', Icons.person, kHealthy),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const Text('Accounts',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 10),
                  ..._users.map((user) => _UserTile(user)),
                  if (_users.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 40),
                      child: Center(
                          child: Text('No users found.',
                              style: TextStyle(color: kMutedFg))),
                    ),
                  const SizedBox(height: 24),
                ],
              ),
      ),
    );
  }
}

class _UserStat extends StatelessWidget {
  final String title, value;
  final IconData icon;
  final Color color;
  const _UserStat(this.title, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w900)),
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: kMutedFg, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  final dynamic user;
  const _UserTile(this.user);

  @override
  Widget build(BuildContext context) {
    final role = '${user['role'] ?? 'user'}'.replaceAll('_', ' ');
    final plan = '${user['subscription_plan'] ?? 'free'}';
    final pending = user['upgrade_requested'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: kPrimary.withOpacity(0.12),
            child: const Icon(Icons.person, color: kPrimary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${user['full_name'] ?? 'Unnamed User'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900)),
                Text('${user['email'] ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: kMutedFg, fontSize: 11)),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 6,
                  children: [
                    _Chip(role),
                    _Chip(plan),
                    if (pending) const _Chip('Pro requested', warning: true),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool warning;
  const _Chip(this.label, {this.warning = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: warning ? Colors.orange.shade50 : kMuted,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: TextStyle(
              color: warning ? Colors.orange.shade800 : kMutedFg,
              fontSize: 10,
              fontWeight: FontWeight.w800)),
    );
  }
}
