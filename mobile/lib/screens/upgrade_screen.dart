import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/auth_provider.dart';
import '../services/theme.dart';

class UpgradeScreen extends StatefulWidget {
  const UpgradeScreen({super.key});

  @override
  State<UpgradeScreen> createState() => _UpgradeScreenState();
}

class _UpgradeScreenState extends State<UpgradeScreen> {
  bool _requesting = false;

  Future<void> _requestUpgrade() async {
    setState(() => _requesting = true);
    try {
      await api.requestUpgrade();
      if (mounted) {
        await context.read<AuthProvider>().refreshUser();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Pro request submitted. Admin can approve it from the web dashboard.'),
          backgroundColor: kHealthy,
        ));
      }
    } catch (e) {
      if (mounted) {
        final isMissingLiveEndpoint =
            e is DioException && e.response?.statusCode == 404;
        if (isMissingLiveEndpoint) {
          context.read<AuthProvider>().markUpgradeRequested();
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
              'Pro request marked as pending. Redeploy the backend so admins can receive it live.',
            ),
            backgroundColor: kFair,
          ));
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_friendlyUpgradeError(e)),
          backgroundColor: kPoor,
        ));
      }
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  String _friendlyUpgradeError(Object e) {
    if (e is DioException) {
      final status = e.response?.statusCode;
      if (status == 401) return 'Please log in again before requesting Pro.';
      if (status == 404) {
        return 'Upgrade request is not available on the live server yet.';
      }
      if (status != null) {
        return 'Upgrade request failed. Server returned status $status.';
      }
      return 'Upgrade request failed. Please check your internet connection.';
    }
    return 'Upgrade request failed. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final isInstitutional = user?.isInstitutional == true;
    final isPro = user?.isPro == true;
    final requested = user?.upgradeRequested == true;

    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        title: Text('Upgrade Pro', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.white,
        foregroundColor: kForeground,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildStatusCard(isInstitutional, isPro, requested),
          const SizedBox(height: 18),
          _buildPlanCard(
            title: 'Starter',
            price: 'Free',
            badge: 'PUBLIC',
            icon: Icons.eco_outlined,
            highlighted: !isPro && !isInstitutional,
            features: const [
              'View public tree map',
              'Scan QR tree profiles',
              'Up to 10 tree records',
              '3 AI identifications per day',
            ],
          ),
          const SizedBox(height: 14),
          _buildPlanCard(
            title: 'Professional',
            price: 'PHP 99 / month',
            badge: 'PRO',
            icon: Icons.workspace_premium_outlined,
            highlighted: isPro,
            features: const [
              'Unlimited AI identification',
              'More tree records',
              'Full dashboard and analytics',
              'Priority unknown-species review',
            ],
          ),
          const SizedBox(height: 14),
          _buildPlanCard(
            title: 'Enterprise',
            price: 'PHP 399+ / month',
            badge: 'LGU / SCHOOL',
            icon: Icons.apartment_outlined,
            highlighted: isInstitutional,
            features: const [
              'Unlimited inventory access',
              'Field worker accounts',
              'Reports for LGU and DENR use',
              'Training and onboarding services',
            ],
          ),
          const SizedBox(height: 22),
          _buildRevenueCard(),
          const SizedBox(height: 24),
          if (!isInstitutional && !isPro)
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: requested || _requesting ? null : _requestUpgrade,
                icon: _requesting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.lock_open_rounded),
                label: Text(requested ? 'Pro Request Pending' : 'Request Pro Upgrade'),
              ),
            ),
          if (isPro || isInstitutional)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: kHealthy.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: kHealthy.withOpacity(0.25)),
              ),
              child: Text(
                isInstitutional
                    ? 'Institutional access is active for this account.'
                    : 'Pro access is active for this account.',
                style: const TextStyle(color: kHealthy, fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(bool isInstitutional, bool isPro, bool requested) {
    final label = isInstitutional
        ? 'Institutional Access'
        : isPro
            ? 'Professional Plan'
            : requested
                ? 'Free Plan - Pro Request Pending'
                : 'Free Plan';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: kSidebarBg,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.payments_outlined, color: kSidebarPrimary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Current Membership',
                    style: TextStyle(color: kSidebarText, fontSize: 12)),
                const SizedBox(height: 4),
                Text(label,
                    style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanCard({
    required String title,
    required String price,
    required String badge,
    required IconData icon,
    required bool highlighted,
    required List<String> features,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: highlighted ? kPrimary : kCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: highlighted ? kPrimary : kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: highlighted ? Colors.white : kPrimary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title,
                    style: GoogleFonts.inter(
                        color: highlighted ? Colors.white : kForeground,
                        fontWeight: FontWeight.w800,
                        fontSize: 16)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: highlighted ? Colors.white.withOpacity(0.14) : kMuted,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(badge,
                    style: TextStyle(
                        color: highlighted ? Colors.white : kPrimary,
                        fontSize: 10,
                        fontWeight: FontWeight.w900)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(price,
              style: GoogleFonts.inter(
                  color: highlighted ? Colors.white : kForeground,
                  fontSize: 20,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          ...features.map((feature) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(Icons.check_circle,
                        size: 16,
                        color: highlighted ? kSidebarPrimary : kHealthy),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(feature,
                          style: TextStyle(
                              color: highlighted ? Colors.white : kForeground,
                              fontSize: 13)),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildRevenueCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Revenue Streams',
              style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          _buildRevenueRow(Icons.school_outlined, 'Training and onboarding services'),
          _buildRevenueRow(Icons.analytics_outlined, 'Data analytics and reporting packages'),
          _buildRevenueRow(Icons.account_balance_outlined, 'Institutional subscriptions for LGUs and schools'),
        ],
      ),
    );
  }

  Widget _buildRevenueRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          Icon(icon, size: 18, color: kPrimary),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}
