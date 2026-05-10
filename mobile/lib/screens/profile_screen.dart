import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/auth_provider.dart';
import '../services/api_service.dart';
import '../services/theme.dart';
import '../models/models.dart';
import 'upgrade_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late Future<int> _queuedCount;
  late Future<List<Map<String, dynamic>>> _aiHistory;
  late Future<List<UnknownSpeciesModel>> _unknownSubmissions;

  @override
  void initState() {
    super.initState();
    _queuedCount = api.queuedCount();
    _aiHistory = api.aiIdentificationHistory();
    _unknownSubmissions = _loadUnknownSubmissions();
  }

  void _refreshQueue() {
    setState(() => _queuedCount = api.queuedCount());
  }

  Future<List<UnknownSpeciesModel>> _loadUnknownSubmissions() async {
    final data = await api.getMyUnknownSpecies();
    return data
        .map((j) => UnknownSpeciesModel.fromJson(Map<String, dynamic>.from(j)))
        .toList();
  }

  void _refreshActivity() {
    setState(() {
      _aiHistory = api.aiIdentificationHistory();
      _unknownSubmissions = _loadUnknownSubmissions();
    });
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
                    _buildPlanCard(user),
                    const SizedBox(height: 24),
                    _buildSectionTitle('My AI Identification Records'),
                    _buildAiHistoryCard(user),
                    const SizedBox(height: 24),
                    _buildSectionTitle('My Unknown Species Submissions'),
                    _buildUnknownSubmissionsCard(),
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

  Widget _buildPlanCard(dynamic user) {
    final isPro = user?.isPro == true;
    final isEnterprise = user?.isEnterprise == true || user?.isInstitutional == true;
    final requested = user?.upgradeRequested == true;
    final aiLimit = isEnterprise
        ? 'unlimited'
        : isPro
            ? '50'
            : '10';
    final unknownLimit = isEnterprise
        ? 'unlimited'
        : isPro
            ? '100'
            : '15';
    final planTitle = isEnterprise
        ? 'Enterprise / Institutional Plan'
        : isPro
        ? 'Professional Plan'
        : requested
            ? 'Free Tier Plan - Pro Request Pending'
            : 'Free Tier Plan';

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
              Expanded(
                child: Text(planTitle,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: kPrimary)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: (isPro || isEnterprise ? kHealthy : Colors.orange).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20)),
                child: Text(isEnterprise ? 'ENTERPRISE' : isPro ? 'PRO' : requested ? 'PENDING' : 'UPGRADE',
                    style: TextStyle(
                        color: isPro || isEnterprise ? kHealthy : Colors.orange,
                        fontSize: 10,
                        fontWeight: FontWeight.w900)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildFeatureRow(Icons.check_circle_outline, 'Public tree map access'),
          _buildFeatureRow(Icons.check_circle_outline, 'Unlimited QR scanner'),
          _buildFeatureRow(Icons.auto_awesome_outlined,
              'AI scans today: ${user?.aiIdentificationsToday ?? 0} / $aiLimit'),
          _buildFeatureRow(Icons.science_outlined,
              'Expert review submissions: ${user?.unknownSubmissionsToday ?? 0} / $unknownLimit'),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const UpgradeScreen()),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: kPrimary,
                side: const BorderSide(color: kPrimary),
                elevation: 0,
              ),
              child: Text(isPro || isEnterprise ? 'View Plan Benefits' : 'View All Plans'),
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

  Widget _buildAiHistoryCard(dynamic user) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _aiHistory,
      builder: (context, snap) {
        final history = snap.data ?? [];
        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: kCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: kBorder),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.auto_awesome_outlined, color: kPrimary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'AI scans today: ${user?.aiIdentificationsToday ?? 0}${user?.isEnterprise == true || user?.isInstitutional == true ? ' / unlimited' : user?.isPro == true ? ' / 50' : ' / 10'}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
              IconButton(
                onPressed: _refreshActivity,
                icon: const Icon(Icons.refresh, size: 18),
              ),
            ]),
            const SizedBox(height: 8),
            if (history.isEmpty)
              const Text(
                'No AI identification records on this phone yet. Scan a tree to start your history.',
                style: TextStyle(color: kMutedFg, fontSize: 12, height: 1.35),
              )
            else
              ...history.take(5).map((item) => _buildAiHistoryTile(item)),
          ]),
        );
      },
    );
  }

  Widget _buildAiHistoryTile(Map<String, dynamic> item) {
    final protected = item['protected'] == true;
    final notIdentified = item['not_identified'] == true;
    final date = DateTime.tryParse(item['created_at']?.toString() ?? '');
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder.withOpacity(0.7)),
      ),
      child: Row(children: [
        Icon(
          notIdentified
              ? Icons.help_outline_rounded
              : protected
                  ? Icons.warning_amber_rounded
                  : Icons.eco_outlined,
          color: protected ? Colors.orange : kPrimary,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              item['common_name']?.toString() ?? 'Unknown species',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            ),
            if (item['scientific_name'] != null)
              Text(
                item['scientific_name'].toString(),
                style: const TextStyle(color: kMutedFg, fontSize: 11, fontStyle: FontStyle.italic),
              ),
            Text(
              '${item['confidence'] ?? 'AI result'} • ${item['status'] ?? 'Not Listed'}${date != null ? ' • ${date.month}/${date.day}/${date.year}' : ''}',
              style: const TextStyle(color: kMutedFg, fontSize: 11),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _buildUnknownSubmissionsCard() {
    return FutureBuilder<List<UnknownSpeciesModel>>(
      future: _unknownSubmissions,
      builder: (context, snap) {
        final submissions = snap.data ?? [];
        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: kCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: kBorder),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.science_outlined, color: kPrimary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${submissions.length} submitted for expert review',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
              IconButton(
                onPressed: _refreshActivity,
                icon: const Icon(Icons.refresh, size: 18),
              ),
            ]),
            const SizedBox(height: 8),
            if (snap.connectionState == ConnectionState.waiting)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: LinearProgressIndicator(color: kPrimary),
              )
            else if (submissions.isEmpty)
              const Text(
                'No unknown species submissions yet. When AI cannot identify a tree, submit it for expert review and track it here.',
                style: TextStyle(color: kMutedFg, fontSize: 12, height: 1.35),
              )
            else
              ...submissions.take(5).map(_buildUnknownSubmissionTile),
          ]),
        );
      },
    );
  }

  Widget _buildUnknownSubmissionTile(UnknownSpeciesModel item) {
    final statusColor = item.reviewed ? kHealthy : Colors.orange;
    final date = item.createdAt;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: statusColor.withOpacity(0.25)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: item.photoUrl?.isNotEmpty == true
              ? Image.network(
                  item.photoUrl!,
                  width: 52,
                  height: 52,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _unknownPhotoFallback(),
                )
              : _unknownPhotoFallback(),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(
                  item.identifiedAs ?? item.possibleName ?? 'Unknown tree',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  item.reviewed ? 'REVIEWED' : 'PENDING',
                  style: TextStyle(color: statusColor, fontSize: 9, fontWeight: FontWeight.w900),
                ),
              ),
            ]),
            Text(
              item.reviewed
                  ? 'Identified as: ${item.identifiedAs ?? 'Reviewed'}'
                  : 'Waiting for admin/expert review',
              style: const TextStyle(color: kMutedFg, fontSize: 11),
            ),
            if (item.reviewNotes?.isNotEmpty == true)
              Text(
                item.reviewNotes!,
                style: const TextStyle(color: kForeground, fontSize: 11),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            Text(
              '${item.barangay ?? 'No barangay'}${date != null ? ' • ${date.month}/${date.day}/${date.year}' : ''}',
              style: const TextStyle(color: kMutedFg, fontSize: 10),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _unknownPhotoFallback() {
    return Container(
      width: 52,
      height: 52,
      color: kPrimary.withOpacity(0.08),
      child: const Icon(Icons.eco_outlined, color: kPrimary),
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
