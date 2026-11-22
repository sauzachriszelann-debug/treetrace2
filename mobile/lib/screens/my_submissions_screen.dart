import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_service.dart';
import '../services/theme.dart';
import 'tree_detail_screen.dart';

/// G4 citizen surface: the caller's own pending tree submissions and their
/// review decisions (approved / rejected / linked), with owner deletion while pending.
class MySubmissionsScreen extends StatefulWidget {
  const MySubmissionsScreen({super.key});

  @override
  State<MySubmissionsScreen> createState() => _MySubmissionsScreenState();
}

class _MySubmissionsScreenState extends State<MySubmissionsScreen> {
  final ApiService api = ApiService();
  late Future<List<_SubmissionItem>> _future;
  int? _deletingId;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<_SubmissionItem>> _load() async {
    final results = await Future.wait(
        [api.getMyTreeSubmissions(), api.getMyUnknownSpecies()]);
    final trees = results[0];
    final converted =
        trees.map((row) => row['source_unknown_species_id']).toSet();
    final data = <dynamic>[
      ...trees,
      for (final row in results[1])
        if (!converted.contains(row['id']))
          {
            ...Map<String, dynamic>.from(row as Map),
            'species_submission': true,
            'status': row['review_status'] == 'closed' ? 'closed' : 'pending',
            'common_name': row['identified_as'] ??
                row['possible_name'] ??
                'Unknown species',
          },
    ];
    data.sort((a, b) =>
        '${b['created_at'] ?? ''}'.compareTo('${a['created_at'] ?? ''}'));
    return data
        .map((j) => _SubmissionItem.fromJson(Map<String, dynamic>.from(j)))
        .toList();
  }

  Future<void> _delete(_SubmissionItem item) async {
    final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Delete this submission?'),
              content: const Text(
                  'This removes the pending entry from My Submissions and the review queue.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Delete')),
              ],
            ));
    if (confirm != true || !mounted || _deletingId != null) return;
    setState(() => _deletingId = item.id);
    try {
      await api.deleteMySubmission(item.id,
          speciesSubmission: item.speciesSubmission);
      if (mounted) await _refresh();
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Could not delete. Refresh to check the submission status.')));
    } finally {
      if (mounted) setState(() => _deletingId = null);
    }
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(title: const Text('My Submissions')),
      body: FutureBuilder<List<_SubmissionItem>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _Message(
              icon: Icons.error_outline_rounded,
              message: 'Could not load your submissions: ${snapshot.error}',
              onRetry: _refresh,
            );
          }
          final items = snapshot.data ?? [];
          if (items.isEmpty) {
            return const _Message(
              icon: Icons.outlined_flag_outlined,
              message:
                  'You have not submitted any trees yet.\nUse AI Scan to submit one for expert review.',
            );
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 110),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) => _SubmissionCard(
                  item: items[index],
                  onDelete:
                      _deletingId == null ? () => _delete(items[index]) : null),
            ),
          );
        },
      ),
    );
  }
}

class _SubmissionItem {
  final int id;
  final bool speciesSubmission;
  final String status;
  final String? commonName;
  final String? barangay;
  final double? lat;
  final double? lng;
  final String? photoUrl;
  final String? reviewReason;
  final String? reviewedByName;
  final DateTime? reviewedAt;
  final DateTime? createdAt;
  final int? approvedTreeId;

  const _SubmissionItem({
    required this.id,
    this.speciesSubmission = false,
    required this.status,
    this.commonName,
    this.barangay,
    this.lat,
    this.lng,
    this.photoUrl,
    this.reviewReason,
    this.reviewedByName,
    this.reviewedAt,
    this.createdAt,
    this.approvedTreeId,
  });

  factory _SubmissionItem.fromJson(Map<String, dynamic> j) => _SubmissionItem(
        id: j['id'] ?? 0,
        speciesSubmission: j['species_submission'] == true,
        status: j['status'] ?? 'pending',
        commonName: j['common_name'],
        barangay: j['barangay'],
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
        photoUrl: j['photo_url'],
        reviewReason: j['review_reason'],
        reviewedByName: j['reviewed_by_name'],
        reviewedAt: j['reviewed_at'] != null
            ? DateTime.tryParse(j['reviewed_at'].toString())
            : null,
        createdAt: j['created_at'] != null
            ? DateTime.tryParse(j['created_at'].toString())
            : null,
        approvedTreeId: j['approved_tree_id'],
      );

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
  bool get isLinked => status == 'linked';
}

class _SubmissionCard extends StatelessWidget {
  final _SubmissionItem item;
  final VoidCallback? onDelete;
  const _SubmissionCard({required this.item, this.onDelete});

  Color get _statusColor {
    if (item.isApproved) return kHealthy;
    if (item.isRejected) return kPoor;
    if (item.isLinked) return Colors.blueGrey;
    return Colors.amber.shade700;
  }

  String get _statusLabel {
    if (item.status == 'closed') return 'Closed as Unresolved';
    if (item.isApproved) return 'Approved';
    if (item.isRejected) return 'Rejected';
    if (item.isLinked) return 'Linked to Existing Tree';
    return 'Pending Review';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.commonName ?? 'Unnamed tree',
                  style: GoogleFonts.fraunces(
                      fontSize: 17, fontWeight: FontWeight.w600),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _statusColor.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _statusLabel,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _statusColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            [
              if (item.barangay != null && item.barangay!.isNotEmpty)
                item.barangay!,
              if (item.lat != null && item.lng != null)
                '${item.lat!.toStringAsFixed(4)}, ${item.lng!.toStringAsFixed(4)}',
              if (item.createdAt != null)
                'Submitted ${item.createdAt!.toLocal()}'.split('.').first,
            ].join(' · '),
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          if (item.photoUrl != null && item.photoUrl!.isNotEmpty) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                item.photoUrl!,
                height: 140,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox(
                  height: 90,
                  child: Center(child: Icon(Icons.broken_image_outlined)),
                ),
              ),
            ),
          ],
          if (item.isPending) ...[
            const SizedBox(height: 10),
            Text(
              'Awaiting review by an admin or field worker.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
          if (item.isPending)
            Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete submission'),
                )),
          if (item.isRejected) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: kPoor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Review decision: ${item.reviewReason ?? 'No reason recorded.'}',
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
          ],
          if ((item.isApproved || item.isLinked) &&
              item.approvedTreeId != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.isApproved
                        ? 'Now an official inventory record.'
                        : 'Matched to an existing inventory record.'
                            '${item.reviewedByName != null ? ' · by ${item.reviewedByName}' : ''}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          TreeDetailScreen(treeId: item.approvedTreeId!),
                    ),
                  ),
                  icon: const Icon(Icons.open_in_new, size: 15),
                  label: const Text('Open Tree'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String message;
  final Future<void> Function()? onRetry;
  const _Message({required this.icon, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 46, color: Colors.grey.shade400),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: Colors.grey.shade600),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}
