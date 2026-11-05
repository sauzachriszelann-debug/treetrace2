import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../services/theme.dart';
import 'unknown_review_screen.dart';

class TreeReviewsScreen extends StatelessWidget {
  final String? role;
  final ApiService? apiOverride;
  final int initialTabIndex;

  const TreeReviewsScreen({
    super.key,
    required this.role,
    this.apiOverride,
    this.initialTabIndex = 0,
  });

  @override
  Widget build(BuildContext context) {
    final normalizedRole = role?.split('.').last.toLowerCase();
    final isAdmin = normalizedRole == 'admin';
    final isStaff = isAdmin || normalizedRole == 'field_worker';
    if (!isStaff) {
      return Scaffold(
        appBar: AppBar(title: const Text('Tree Reviews')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('Staff access is required to review tree records.'),
          ),
        ),
      );
    }

    final service = apiOverride ?? api;
    return DefaultTabController(
      length: 2,
      initialIndex: initialTabIndex.clamp(0, 1).toInt(),
      child: Scaffold(
        backgroundColor: kBackground,
        appBar: AppBar(
          toolbarHeight: 52,
          title: const Text('Tree Reviews'),
          bottom: const TabBar(
            isScrollable: false,
            labelColor: Colors.white,
            unselectedLabelColor: Color(0x99FFFFFF),
            indicatorColor: kSidebarPrimary,
            indicatorWeight: 3,
            dividerColor: Colors.transparent,
            labelStyle: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            unselectedLabelStyle:
                TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
            tabs: [
              Tab(height: 44, text: 'Tree Submissions'),
              Tab(height: 44, text: 'Unknown Species'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _TreeSubmissionsTab(api: service),
            if (isAdmin)
              UnknownReviewScreen(apiOverride: service, embedded: true)
            else
              const _RestrictedUnknownReviews(),
          ],
        ),
      ),
    );
  }
}

class _RestrictedUnknownReviews extends StatelessWidget {
  const _RestrictedUnknownReviews();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.admin_panel_settings_outlined,
                size: 42, color: kMutedFg),
            SizedBox(height: 12),
            Text(
              'Unknown Species review is available to administrators only.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _TreeSubmissionsTab extends StatefulWidget {
  final ApiService api;

  const _TreeSubmissionsTab({required this.api});

  @override
  State<_TreeSubmissionsTab> createState() => _TreeSubmissionsTabState();
}

class _TreeSubmissionsTabState extends State<_TreeSubmissionsTab> {
  static const _statuses = [
    ('pending', 'Pending'),
    ('approved', 'Approved'),
    ('rejected', 'Rejected'),
    ('linked', 'Linked'),
    ('all', 'All'),
  ];

  List<TreeSubmissionModel> _items = [];
  String _status = 'pending';
  String? _loadError;
  int? _busyId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final data = await widget.api.getTreeSubmissions(status: _status);
      if (!mounted) return;
      setState(() {
        _items = data
            .map((item) => TreeSubmissionModel.fromJson(
                Map<String, dynamic>.from(item as Map)))
            .toList();
        _loadError = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = _reviewError(error);
        _loading = false;
      });
    }
  }

  Future<void> _runAction(
    TreeSubmissionModel item,
    Future<void> Function() action,
    String successMessage,
  ) async {
    if (_busyId != null) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busyId = item.id);
    try {
      await action();
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(successMessage),
        backgroundColor: kHealthy,
      ));
      await _load(showLoading: false);
    } catch (error) {
      if (mounted && messenger.mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text(_reviewError(error)),
          backgroundColor: kPoor,
        ));
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _approve(TreeSubmissionModel item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Approve submission?'),
        content: Text(
          '${item.commonName?.trim().isNotEmpty == true ? item.commonName : 'This submission'} will become an official tree record. This cannot be undone here.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _runAction(
      item,
      () async {
        await widget.api.approveTreeSubmission(item.id);
      },
      'Submission approved.',
    );
  }

  Future<void> _reject(TreeSubmissionModel item) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _RejectSubmissionDialog(),
    );
    if (reason == null || !mounted) return;
    await _runAction(
      item,
      () async {
        await widget.api.rejectTreeSubmission(item.id, reason: reason);
      },
      'Submission rejected.',
    );
  }

  Future<void> _link(TreeSubmissionModel item) async {
    final messenger = ScaffoldMessenger.of(context);
    List<dynamic> rawTrees;
    try {
      rawTrees = await widget.api.getTrees(limit: 1000);
    } catch (error) {
      if (mounted && messenger.mounted) {
        messenger.showSnackBar(SnackBar(
          content:
              Text('Could not load existing trees: ${_reviewError(error)}'),
          backgroundColor: kPoor,
        ));
      }
      return;
    }
    if (!mounted) return;
    final trees = rawTrees
        .whereType<Map>()
        .map((tree) => Map<String, dynamic>.from(tree))
        .toList();
    if (trees.isEmpty) {
      messenger.showSnackBar(const SnackBar(
        content: Text('There are no existing trees to link to.'),
      ));
      return;
    }
    final treeId = await showDialog<int>(
      context: context,
      builder: (_) => _ExistingTreePicker(trees: trees),
    );
    if (treeId == null || !mounted) return;
    final target = trees.firstWhere(
      (tree) => (tree['id'] as num?)?.toInt() == treeId,
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Link to existing tree?'),
        content: Text(
          'Link this submission to ${target['common_name'] ?? 'tree'} #$treeId? No tree record will be created or changed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirm link'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _runAction(
      item,
      () async {
        await widget.api.linkTreeSubmission(item.id, treeId: treeId);
      },
      'Submission linked to tree #$treeId.',
    );
  }

  Future<void> _reopen(TreeSubmissionModel item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reopen submission?'),
        content: const Text('This rejected submission will return to Pending.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Reopen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _runAction(
      item,
      () async {
        await widget.api.reopenTreeSubmission(item.id);
      },
      'Submission reopened.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () => _load(showLoading: false),
      color: kPrimary,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            sliver: SliverToBoxAdapter(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (value, label) in _statuses)
                    _ReviewFilterChip(
                      label: label,
                      selected: _status == value,
                      onSelected: _loading || _busyId != null
                          ? null
                          : () {
                              setState(() => _status = value);
                              _load();
                            },
                    ),
                ],
              ),
            ),
          ),
          if (_loading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator(color: kPrimary)),
            )
          else if (_loadError != null)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _QueueState(
                icon: Icons.cloud_off_outlined,
                message: _loadError!,
                actionLabel: 'Try again',
                onAction: _load,
              ),
            )
          else if (_items.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _QueueState(
                icon: Icons.park_outlined,
                message: 'No tree submissions in this view.',
                actionLabel: 'Refresh',
                onAction: () => _load(showLoading: false),
              ),
            )
          else ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
              sliver: SliverToBoxAdapter(
                child: Text(
                  '${_items.length} ${_status == 'all' ? '' : '$_status '}submission${_items.length == 1 ? '' : 's'}',
                  style: const TextStyle(
                    color: kMutedFg,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
              sliver: SliverList.builder(
                itemCount: _items.length,
                itemBuilder: (_, index) => _submissionCard(_items[index]),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _submissionCard(TreeSubmissionModel item) {
    final busy = _busyId == item.id;
    final canReview = item.status == 'pending' && !busy;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: .04),
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ReviewPhoto(url: item.photoUrl),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                              item.commonName?.trim().isNotEmpty == true
                                  ? item.commonName!
                                  : 'Unnamed submission #${item.id}',
                              style: const TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.w900)),
                          _StatusChip(status: item.status),
                          if (item.source?.isNotEmpty == true)
                            Chip(label: Text(item.source!)),
                        ],
                      ),
                      if (item.scientificName?.isNotEmpty == true)
                        Text(item.scientificName!,
                            style: const TextStyle(
                                fontStyle: FontStyle.italic, color: kMutedFg)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _detailLine(Icons.location_on_outlined, _location(item)),
            _detailLine(Icons.person_outline_rounded,
                _submitter(item.submittedByName, item.submittedByEmail)),
            _detailLine(Icons.calendar_today_outlined,
                'Submitted ${_dateLabel(item.createdAt)}'),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _measurement('DBH', item.dbhCm, 'cm'),
                _measurement('Height', item.heightM, 'm'),
                if (item.healthStatus?.isNotEmpty == true)
                  _measurementLabel('Health', item.healthStatus!),
                if (item.dateRecorded?.isNotEmpty == true)
                  _measurementLabel('Recorded', item.dateRecorded!),
              ],
            ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Full details'),
              children: [
                _detailLine(Icons.gps_fixed_rounded, _coordinates(item)),
                if (item.notes?.isNotEmpty == true)
                  _detailLine(Icons.notes_outlined, item.notes!),
                if (item.reviewedByName?.isNotEmpty == true)
                  _detailLine(Icons.verified_user_outlined,
                      'Reviewed by ${item.reviewedByName}'),
                if (item.reviewedAt != null)
                  _detailLine(Icons.schedule,
                      'Reviewed ${_dateLabel(item.reviewedAt)}'),
                if (item.reviewReason?.isNotEmpty == true)
                  _detailLine(Icons.info_outline, item.reviewReason!),
                if (item.approvedTreeId != null)
                  _detailLine(
                      Icons.link, 'Linked tree #${item.approvedTreeId}'),
                if (item.reviewOverrides?.isNotEmpty == true)
                  _detailLine(Icons.edit_note_outlined,
                      'Reviewer corrections: ${item.reviewOverrides}'),
                if (item.aiCandidates.isNotEmpty)
                  _candidateList(item.aiCandidates),
              ],
            ),
            if (busy)
              const LinearProgressIndicator(minHeight: 2)
            else if (canReview)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _link(item),
                    icon: const Icon(Icons.link, size: 18),
                    label: const Text('Link existing tree'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _reject(item),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('Reject'),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _approve(item),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Approve'),
                  ),
                ],
              )
            else if (item.status == 'rejected')
              OutlinedButton.icon(
                onPressed: _busyId == null ? () => _reopen(item) : null,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Reopen'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _detailLine(IconData icon, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: kMutedFg),
            const SizedBox(width: 8),
            Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
          ],
        ),
      );

  Widget _measurement(String label, double? value, String unit) =>
      _measurementLabel(label, value == null ? '—' : '${_number(value)} $unit');

  Widget _measurementLabel(String label, String value) => Chip(
        visualDensity: VisualDensity.compact,
        label: Text('$label: $value'),
      );

  Widget _candidateList(List<dynamic> candidates) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('AI candidates',
                style: TextStyle(fontWeight: FontWeight.w700)),
            for (final candidate in candidates.take(5))
              Text(_candidateLabel(candidate),
                  style: const TextStyle(fontSize: 12, color: kMutedFg)),
          ],
        ),
      );
}

class _RejectSubmissionDialog extends StatefulWidget {
  const _RejectSubmissionDialog();

  @override
  State<_RejectSubmissionDialog> createState() =>
      _RejectSubmissionDialogState();
}

class _RejectSubmissionDialogState extends State<_RejectSubmissionDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Reject submission?'),
        content: TextField(
          controller: _controller,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Reason (required)',
            hintText: 'Explain why this submission is rejected',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (_, value, __) => ElevatedButton(
              onPressed: value.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(context, value.text.trim()),
              child: const Text('Confirm reject'),
            ),
          ),
        ],
      );
}

class _ExistingTreePicker extends StatefulWidget {
  final List<Map<String, dynamic>> trees;

  const _ExistingTreePicker({required this.trees});

  @override
  State<_ExistingTreePicker> createState() => _ExistingTreePickerState();
}

class _ExistingTreePickerState extends State<_ExistingTreePicker> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final search = _searchController.text.trim().toLowerCase();
    final filtered = widget.trees.where((tree) {
      if (search.isEmpty) return true;
      final searchable = [
        tree['id'],
        tree['common_name'],
        tree['scientific_name'],
        tree['barangay'],
        tree['city'],
      ].join(' ').toLowerCase();
      return searchable.contains(search);
    }).toList();
    return AlertDialog(
      title: const Text('Choose an existing tree'),
      content: SizedBox(
        width: 420,
        height: 440,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search name, location, or ID',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(child: Text('No matching trees.'))
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (_, index) {
                        final tree = filtered[index];
                        final id = (tree['id'] as num?)?.toInt();
                        if (id == null) return const SizedBox.shrink();
                        final commonName =
                            tree['common_name']?.toString() ?? 'Unnamed tree';
                        final location = [tree['barangay'], tree['city']]
                            .whereType<String>()
                            .where((part) => part.isNotEmpty)
                            .join(', ');
                        return ListTile(
                          title: Text('$commonName · #$id'),
                          subtitle: Text(location.isEmpty
                              ? 'Location unavailable'
                              : location),
                          onTap: () => Navigator.pop(context, id),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final normalized = status.toLowerCase();
    final (background, foreground) = switch (normalized) {
      'approved' => (const Color(0xFFE5F4E9), const Color(0xFF17633A)),
      'rejected' => (const Color(0xFFFCE8E8), const Color(0xFFB42318)),
      'linked' => (const Color(0xFFE7F0FA), const Color(0xFF245B83)),
      _ => (const Color(0xFFFFF2D6), const Color(0xFF805000)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _titleCase(status),
        style: TextStyle(
          color: foreground,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ReviewFilterChip extends StatelessWidget {
  const _ReviewFilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback? onSelected;

  @override
  Widget build(BuildContext context) => ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: true,
        checkmarkColor: Colors.white,
        onSelected: onSelected == null ? null : (_) => onSelected!(),
        backgroundColor: const Color(0xFFF0F4F1),
        selectedColor: const Color(0xFF1E3A2B),
        side: BorderSide.none,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        labelStyle: TextStyle(
          color: selected ? Colors.white : const Color(0xFF1E3A2B),
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          fontSize: 13,
        ),
      );
}

class _ReviewPhoto extends StatelessWidget {
  const _ReviewPhoto({required this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    final usable = url?.trim().isNotEmpty == true;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox.square(
        dimension: 56,
        child: usable
            ? Image.network(
                url!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _fallback(),
              )
            : _fallback(),
      ),
    );
  }

  Widget _fallback() => Container(
        color: const Color(0xFFEAF1EB),
        alignment: Alignment.center,
        child: const Icon(Icons.park_outlined, color: kPrimary, size: 25),
      );
}

class _QueueState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _QueueState({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 38, horizontal: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 42, color: kMutedFg),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      );
}

String _reviewError(Object error) {
  if (isConnectionFailure(error)) {
    return 'Cannot reach TreeTrace. Check your connection and try again.';
  }
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['detail'] != null) {
      final detail = data['detail'];
      if (detail is Map && detail['message'] != null) {
        return detail['message'].toString();
      }
      if (detail is String && detail.trim().isNotEmpty) return detail;
    }
    if (error.response?.statusCode == 403) {
      return 'Your account is not allowed to perform this review action.';
    }
    if (error.response?.statusCode == 409) {
      return 'This submission changed in another review. Refresh the list and try again.';
    }
  }
  return 'Could not complete the review action. Please try again.';
}

String _location(TreeSubmissionModel item) {
  final parts = [item.barangay, item.city, item.province]
      .whereType<String>()
      .where((part) => part.trim().isNotEmpty)
      .toList();
  return parts.isEmpty ? 'Location not provided' : parts.join(', ');
}

String _submitter(String? name, String? email) {
  final pieces = [name, email]
      .whereType<String>()
      .where((part) => part.trim().isNotEmpty)
      .toList();
  return pieces.isEmpty
      ? 'Submitter information unavailable'
      : pieces.join(' · ');
}

String _coordinates(TreeSubmissionModel item) {
  if (item.lat == null || item.lng == null) {
    return 'GPS coordinates not provided';
  }
  return 'GPS ${item.lat!.toStringAsFixed(5)}, ${item.lng!.toStringAsFixed(5)}';
}

String _dateLabel(DateTime? date) => date == null
    ? 'Date unavailable'
    : DateFormat.yMMMMd().format(date.toLocal());

String _number(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(1)
    : value.toStringAsFixed(2);

String _titleCase(String value) => value.isEmpty
    ? value
    : '${value[0].toUpperCase()}${value.substring(1).toLowerCase()}';

String _candidateLabel(dynamic candidate) {
  if (candidate is! Map) return candidate.toString();
  final name = candidate['common_name'] ?? candidate['name'] ?? 'Candidate';
  final scientific = candidate['scientific_name'];
  final confidence = candidate['confidence_percent'] ??
      candidate['confidence'] ??
      candidate['score'];
  final pieces = <String>[name.toString()];
  if (scientific != null && scientific.toString().trim().isNotEmpty) {
    pieces.add(scientific.toString());
  }
  if (confidence is num) {
    pieces.add(
        '${(confidence > 1 ? confidence : confidence * 100).toStringAsFixed(1)}%');
  } else if (confidence is String && confidence.trim().isNotEmpty) {
    pieces.add(confidence);
  }
  return pieces.join(' · ');
}
