import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/auth_provider.dart';
import '../services/api_service.dart';
import '../services/theme.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late Future<int> _queuedCount;

  @override
  void initState() {
    super.initState();
    _queuedCount = api.queuedCount();
  }

  void _refreshQueue() {
    setState(() => _queuedCount = api.queuedCount());
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;

    return Scaffold(
      backgroundColor: kBackground,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          _buildHeader(user),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildSectionTitle('Account Information'),
                  _buildAccountCard(user),
                  const SizedBox(height: 24),
                  _buildSectionTitle('Field Sync'),
                  _buildOfflineSyncCard(context),
                  const SizedBox(height: 24),
                  if (user?.role == 'citizen') ...[
                    _buildSectionTitle('Membership Status'),
                    _buildPlanCard(),
                    const SizedBox(height: 24),
                  ],
                  _buildSettingsSection(auth),
                  const SizedBox(height: 40),
                  _buildAppVersion(),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(dynamic user) {
    return SliverAppBar(
      expandedHeight: 240,
      pinned: true,
      stretch: true,
      backgroundColor: kSidebarBg,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1a3323), Color(0xFF2d6b3a), Color(0xFF3a8a4a)],
            ),
          ),
          child: SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: CircleAvatar(
                    radius: 45,
                    backgroundColor: Colors.white,
                    child: Text(
                      user?.fullName.isNotEmpty == true ? user!.fullName[0].toUpperCase() : '?',
                      style: GoogleFonts.inter(color: kPrimary, fontSize: 32, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  user?.fullName ?? 'Guest User',
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Text(
                    user?.role == 'citizen' ? 'Citizen Explorer' : user?.role?.toUpperCase() ?? 'USER',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800, color: kMutedFg, letterSpacing: 1.2),
      ),
    );
  }

  Widget _buildAccountCard(dynamic user) {
    return Container(
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kBorder),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          _buildInfoTile(Icons.alternate_email_rounded, 'Email Address', user?.email ?? 'Not available', true),
          _buildInfoTile(Icons.verified_user_outlined, 'Account Role', user?.role ?? 'Citizen', true),
          _buildInfoTile(Icons.calendar_today_outlined, 'Member Since', 'Oct 2024', false),
        ],
      ),
    );
  }

  Widget _buildInfoTile(IconData icon, String label, String value, bool showDivider) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: kBackground, borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, size: 20, color: kPrimary),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(color: kMutedFg, fontSize: 12)),
                    const SizedBox(height: 2),
                    Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (showDivider) Divider(height: 1, indent: 60, color: kBorder.withOpacity(0.5)),
      ],
    );
  }

  Widget _buildPlanCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [kPrimary.withOpacity(0.05), kPrimary.withOpacity(0.1)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kPrimary.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Free Tier Plan', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: kPrimary)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Colors.orange.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
                child: const Text('UPGRADE', style: TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.w900)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildFeatureRow(Icons.check_circle_outline, 'Public tree map access'),
          _buildFeatureRow(Icons.check_circle_outline, 'QR scanner enabled'),
          _buildFeatureRow(Icons.lock_outline, 'Unlimited AI scans (Pro Only)', isLocked: true),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: kPrimary,
                side: const BorderSide(color: kPrimary),
                elevation: 0,
              ),
              child: const Text('View All Plans'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureRow(IconData icon, String text, {bool isLocked = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: isLocked ? kMutedFg : kPrimary),
          const SizedBox(width: 10),
          Text(text, style: TextStyle(fontSize: 13, color: isLocked ? kMutedFg : kForeground)),
        ],
      ),
    );
  }

  Widget _buildSettingsSection(AuthProvider auth) {
    return Column(
      children: [
        _buildSettingsTile(Icons.notifications_none_rounded, 'Notifications', () {}),
        _buildSettingsTile(Icons.security_rounded, 'Privacy & Security', () {}),
        _buildSettingsTile(Icons.help_outline_rounded, 'Help Center', () {}),
        const SizedBox(height: 12),
        _buildSettingsTile(Icons.logout_rounded, 'Sign Out', () => auth.logout(), isDestructive: true),
      ],
    );
  }

  Widget _buildOfflineSyncCard(BuildContext context) {
    return FutureBuilder<int>(
      future: _queuedCount,
      builder: (context, snap) {
        final count = snap.data ?? 0;
        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: kCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: count > 0 ? Colors.orange.withOpacity(0.35) : kBorder),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(count > 0 ? Icons.cloud_upload_outlined : Icons.cloud_done_outlined,
                  color: count > 0 ? Colors.orange : kPrimary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  count > 0 ? '$count pending field record${count == 1 ? '' : 's'}' : 'All field records synced',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Text(
              count > 0
                  ? 'Saved offline records will upload automatically when your signal returns.'
                  : 'Offline tree and unknown-species submissions are ready for remote barangay work.',
              style: const TextStyle(color: kMutedFg, fontSize: 12, height: 1.35),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final synced = await api.syncOfflineQueue();
                  _refreshQueue();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(synced > 0
                        ? 'Synced $synced offline record${synced == 1 ? '' : 's'}.'
                        : 'No offline records synced yet.'),
                    backgroundColor: synced > 0 ? kHealthy : kMutedFg,
                  ));
                },
                icon: const Icon(Icons.sync),
                label: const Text('Sync Now'),
              ),
            ),
          ]),
        );
      },
    );
  }

  Widget _buildSettingsTile(IconData icon, String title, VoidCallback onTap, {bool isDestructive = false}) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: isDestructive ? kPoor : kMutedFg),
      title: Text(title, style: TextStyle(color: isDestructive ? kPoor : kForeground, fontWeight: FontWeight.w500)),
      trailing: const Icon(Icons.chevron_right_rounded, color: kBorder),
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }

  Widget _buildAppVersion() {
    return Column(
      children: [
        const Text('TreeTrace Explorer', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: kMutedFg)),
        const SizedBox(height: 4),
        Text('Version 1.0.0 (Build 12)', style: TextStyle(fontSize: 11, color: kMutedFg.withOpacity(0.6))),
      ],
    );
  }
}
