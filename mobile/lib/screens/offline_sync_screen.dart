import 'dart:io';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/offline_queue.dart';
import '../services/theme.dart';
import '../widgets/widgets.dart';

class OfflineSyncScreen extends StatefulWidget {
  const OfflineSyncScreen({super.key, this.debugService, this.debugIsOnline});

  /// G6 test seams: injected queue service / connectivity check.
  @visibleForTesting
  final OfflineQueueService? debugService;
  @visibleForTesting
  final Future<bool> Function()? debugIsOnline;

  @override
  State<OfflineSyncScreen> createState() => _OfflineSyncScreenState();
}

class _OfflineSyncScreenState extends State<OfflineSyncScreen> {
  OfflineQueueService? _service;
  List<OfflineQueueItem> _items = [];
  bool _loading = true;
  bool _syncing = false;
  bool? _online;
  String? _quarantineNotice;
  SyncResult? _result;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<OfflineQueueService> _ensureService() async =>
      widget.debugService ?? await api.offlineQueueService;

  Future<void> _load() async {
    final service = await _ensureService();
    final online =
        await (widget.debugIsOnline ?? api.isOnline)();
    final items = await service.all();
    if (!mounted) return;
    setState(() {
      _service = service;
      _items = items;
      _online = online;
      _quarantineNotice = service.corruptionNotice;
      if (_result == null && widget.debugService == null) {
        _result = api.lastSyncResult;
      }
      _loading = false;
    });
  }

  Future<void> _setVerified(OfflineQueueItem item, bool value) async {
    final service = _service;
    if (service == null) return;
    await service.setVerified(item.itemId, value);
    await _load();
  }

  Future<void> _verifyAll() async {
    final service = _service;
    if (service == null) return;
    await service.verifyAll();
    await _load();
  }

  Future<void> _deleteItem(OfflineQueueItem item) async {
    final service = _service;
    if (service == null) return;
    await service.remove(item.itemId);
    await _load();
  }

  Future<void> _retryItem(OfflineQueueItem item) async {
    final service = _service;
    if (service == null) return;
    await service.resolveForManualRetry(item.itemId);
    await _load();
    if (item.verified && _online == true) {
      await _sync();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Hold cleared. Verify the record, then sync.'),
          backgroundColor: kMutedFg));
    }
  }

  Future<void> _continueWithoutPhoto(OfflineQueueItem item) async {
    final service = _service;
    if (service == null) return;
    await service.continueWithoutPhoto(item.itemId);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Photo will not be uploaded. The record itself will sync.'),
          backgroundColor: kMutedFg));
    }
  }

  Future<void> _sync() async {
    final service = _service;
    if (service == null || _syncing) return;
    setState(() => _syncing = true);
    final SyncResult result;
    if (widget.debugService != null) {
      result = await service.sync(auto: false);
    } else {
      result = await api.syncOfflineQueue();
    }
    await _load();
    if (!mounted) return;
    setState(() {
      _syncing = false;
      _result = result;
    });
    final messenger = ScaffoldMessenger.of(context);
    if (result.alreadyRunning) {
      messenger.showSnackBar(const SnackBar(
          content: Text('A sync is already running.'),
          backgroundColor: kMutedFg));
    } else if (result.offline) {
      messenger.showSnackBar(const SnackBar(
          content: Text(
              'You are offline. Verified records will sync when the connection returns.'),
          backgroundColor: kMutedFg));
    } else if (result.authError != null) {
      messenger.showSnackBar(SnackBar(
          content: Text(result.authError!),
          backgroundColor: kPoor));
    } else if (result.ran && result.synced > 0) {
      messenger.showSnackBar(SnackBar(
          content: Text(
              'Synced ${result.synced} record${result.synced == 1 ? '' : 's'}.'),
          backgroundColor: kHealthy));
    } else {
      messenger.showSnackBar(const SnackBar(
          content: Text('No records were synced.'),
          backgroundColor: kMutedFg));
    }
  }

  @override
  Widget build(BuildContext context) {
    final verifiedCount = _items.where((i) => i.verified).length;
    final reviewCount = _items.where((i) => i.requiresReview).length;
    final syncableCount =
        _items.where((i) => i.verified && !i.requiresReview).length;
    final canSync = syncableCount > 0 && !_syncing && _online != false;
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        title: const Text('Field Sync Review'),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : RefreshIndicator(
              onRefresh: _load,
              color: kPrimary,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                children: [
                  if (_online == false) ...[
                    const _InfoBanner(
                      icon: Icons.cloud_off_rounded,
                      color: kFair,
                      text:
                          'Offline. Verified records wait here and sync automatically when the connection returns.',
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (_quarantineNotice != null) ...[
                    _InfoBanner(
                      icon: Icons.warning_amber_rounded,
                      color: kPoor,
                      text: _quarantineNotice!,
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (_result != null) ...[
                    _ResultBanner(result: _result!),
                    const SizedBox(height: 10),
                  ],
                  _SyncSummary(
                    total: _items.length,
                    verified: verifiedCount,
                    needsReview: reviewCount,
                    onVerifyAll: _items.isEmpty ? null : _verifyAll,
                    onSync: canSync ? _sync : null,
                    syncing: _syncing,
                  ),
                  const SizedBox(height: 14),
                  if (_items.isEmpty)
                    const EmptyState(
                      message: 'No offline records waiting for sync.',
                      subtitle:
                          'New offline trees, submissions, health logs, unknown species, and planting suggestions will appear here for review.',
                      icon: Icons.cloud_done_outlined,
                    )
                  else
                    ..._items.map((item) => _OfflineQueueCard(
                          item: item,
                          onChanged: (value) => _setVerified(item, value),
                          onDelete: () => _deleteItem(item),
                          onRetry: () => _retryItem(item),
                          onContinueWithoutPhoto: () =>
                              _continueWithoutPhoto(item),
                        )),
                ],
              ),
            ),
    );
  }
}

// ── Banners ──────────────────────────────────────────────────────────────────

class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _InfoBanner({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 9),
          Expanded(
            child: Text(text,
                style:
                    const TextStyle(color: kForeground, fontSize: 12.5, height: 1.4)),
          ),
        ],
      ),
    );
  }
}

class _ResultBanner extends StatelessWidget {
  final SyncResult result;
  const _ResultBanner({required this.result});

  @override
  Widget build(BuildContext context) {
    if (result.authError != null) {
      return _InfoBanner(
        icon: Icons.lock_outline_rounded,
        color: kPoor,
        text:
            'Session expired - sign in again to resume sync. All queued records and photos are kept on this device. (${result.authError})',
      );
    }
    if (result.alreadyRunning || (!result.ran && !result.offline)) {
      return const SizedBox.shrink();
    }
    final parts = <String>[
      if (result.ran) 'Synced ${result.synced}.',
      if (result.keptForRetry > 0)
        '${result.keptForRetry} waiting to retry (temporary problem).',
      if (result.heldForReview > 0)
        '${result.heldForReview} held for your review - never retried automatically.',
      if (result.skippedUnverified > 0)
        '${result.skippedUnverified} skipped: not verified yet.',
      if (result.skippedBackoff > 0)
        '${result.skippedBackoff} in backoff after repeated failures.',
    ];
    if (parts.isEmpty && !result.offline) return const SizedBox.shrink();
    return _InfoBanner(
      icon: result.offline ? Icons.cloud_off_rounded : Icons.sync_rounded,
      color: result.heldForReview > 0 ? kFair : kPrimary,
      text: [
        if (result.offline) 'Offline - nothing was sent.',
        ...parts,
      ].join(' '),
    );
  }
}

// ── Summary ──────────────────────────────────────────────────────────────────

class _SyncSummary extends StatelessWidget {
  final int total;
  final int verified;
  final int needsReview;
  final VoidCallback? onVerifyAll;
  final VoidCallback? onSync;
  final bool syncing;
  const _SyncSummary({
    required this.total,
    required this.verified,
    required this.needsReview,
    required this.onVerifyAll,
    required this.onSync,
    required this.syncing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: total > 0 ? kFair.withOpacity(0.35) : kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                total > 0 ? Icons.rule_folder_outlined : Icons.cloud_done_outlined,
                color: total > 0 ? kFair : kPrimary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$verified of $total verified${needsReview > 0 ? ' · $needsReview need review' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Review each offline record before uploading. Only verified items sync - automatically when you reconnect, or now with Sync Verified. Items marked "needs review" are never retried automatically.',
            style: TextStyle(color: kMutedFg, fontSize: 12, height: 1.35),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onVerifyAll,
                  icon: const Icon(Icons.done_all_rounded, size: 17),
                  label: const Text('Verify All'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onSync,
                  icon: syncing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_upload_outlined, size: 17),
                  label: Text(syncing ? 'Syncing' : 'Sync Verified'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Item card ────────────────────────────────────────────────────────────────

const Map<String, String> _reviewLabels = {
  QueueFailureKind.ambiguous: 'Possible duplicate - review',
  QueueFailureKind.conflict: 'Conflicts with a record',
  QueueFailureKind.validation: 'Server rejected this record',
  QueueFailureKind.role: 'Not allowed for this account',
  QueueFailureKind.missingPhoto: 'Photo missing on device',
  QueueFailureKind.retriesExhausted: 'Automatic retries paused',
  QueueFailureKind.unknown: 'Needs review',
};

class _OfflineQueueCard extends StatelessWidget {
  final OfflineQueueItem item;
  final ValueChanged<bool> onChanged;
  final VoidCallback onDelete;
  final VoidCallback onRetry;
  final VoidCallback onContinueWithoutPhoto;

  const _OfflineQueueCard({
    required this.item,
    required this.onChanged,
    required this.onDelete,
    required this.onRetry,
    required this.onContinueWithoutPhoto,
  });

  @override
  Widget build(BuildContext context) {
    final payload = item.payload;
    final photoMissing = item.hasPhoto &&
        !item.photoUploaded &&
        !File(item.photoPath!).existsSync();
    final reviewLabel = item.requiresReview
        ? (_reviewLabels[item.lastErrorKind] ?? 'Needs review')
        : null;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: item.requiresReview
                ? kPoor.withValues(alpha: 0.5)
                : item.verified
                    ? kHealthy.withValues(alpha: 0.35)
                    : kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _OfflinePhoto(path: item.photoPath, type: item.type),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _titleFor(item.type, payload),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _labelFor(item.type),
                      style: const TextStyle(
                        color: kPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                    Text(
                      _formatDate(item.createdAt),
                      style:
                          const TextStyle(color: kMutedFg, fontSize: 10.5),
                    ),
                  ],
                ),
              ),
              Switch(
                value: item.verified,
                activeColor: kHealthy,
                onChanged: onChanged,
              ),
            ],
          ),
          if (reviewLabel != null) ...[
            const SizedBox(height: 8),
            _InfoBanner(
              icon: Icons.priority_high_rounded,
              color: kPoor,
              text: '$reviewLabel. ${item.lastError ?? ''}',
            ),
          ] else if (item.lastError != null && item.attempts > 0) ...[
            const SizedBox(height: 8),
            Text(
              'Last error: ${item.lastError} (attempt ${item.attempts})',
              style: const TextStyle(color: kMutedFg, fontSize: 11.5, height: 1.35),
            ),
          ],
          if (photoMissing) ...[
            const SizedBox(height: 8),
            const _InfoBanner(
              icon: Icons.broken_image_outlined,
              color: kFair,
              text:
                  'The photo for this record is missing on this device. It will not upload until you continue without it or remove the record.',
            ),
          ],
          const SizedBox(height: 10),
          _PayloadPreview(payload: payload),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  item.verified
                      ? (item.requiresReview
                          ? 'Verified - held for review'
                          : 'Verified for sync')
                      : 'Needs your verification',
                  style: TextStyle(
                    color: item.verified
                        ? item.requiresReview
                            ? kPoor
                            : kHealthy
                        : kFair,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (item.requiresReview && item.verified) ...[
                TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.replay_rounded, size: 16),
                  label: const Text('Retry once'),
                  style: TextButton.styleFrom(foregroundColor: kPrimary),
                ),
              ],
              if (item.lastErrorKind == QueueFailureKind.missingPhoto) ...[
                TextButton.icon(
                  onPressed: onContinueWithoutPhoto,
                  icon: const Icon(Icons.photo_library_outlined, size: 16),
                  label: const Text('Sync w/o photo'),
                  style: TextButton.styleFrom(foregroundColor: kFair),
                ),
              ],
              TextButton.icon(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded, size: 16),
                label: const Text('Remove'),
                style: TextButton.styleFrom(foregroundColor: kPoor),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(String iso) {
    final createdAt = DateTime.tryParse(iso);
    if (createdAt == null) return '';
    return '${createdAt.month}/${createdAt.day}/${createdAt.year} '
        '${createdAt.hour.toString().padLeft(2, '0')}:'
        '${createdAt.minute.toString().padLeft(2, '0')}';
  }
}

class _PayloadPreview extends StatelessWidget {
  final Map<String, dynamic> payload;
  const _PayloadPreview({required this.payload});

  @override
  Widget build(BuildContext context) {
    final rows = payload.entries
        .where((entry) =>
            entry.value != null && entry.value.toString().trim().isNotEmpty)
        .take(5)
        .toList();
    if (rows.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: kBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        children: rows
            .map((entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 90,
                        child: Text(
                          _prettyKey(entry.key),
                          style: const TextStyle(
                            color: kMutedFg,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          entry.value.toString(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }
}

class _OfflinePhoto extends StatelessWidget {
  final String? path;
  final String type;
  const _OfflinePhoto({required this.path, required this.type});

  @override
  Widget build(BuildContext context) {
    final file = (path != null && path!.isNotEmpty) ? File(path!) : null;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: file != null && file.existsSync()
          ? Image.file(file, width: 58, height: 58, fit: BoxFit.cover)
          : Container(
              width: 58,
              height: 58,
              color: kPrimary.withValues(alpha: 0.08),
              child: Icon(_iconFor(type), color: kPrimary),
            ),
    );
  }
}

String _titleFor(String type, Map<String, dynamic> payload) {
  return payload['common_name']?.toString() ??
      payload['species_name']?.toString() ??
      payload['possible_name']?.toString() ??
      payload['scientific_name']?.toString() ??
      'Offline record';
}

String _labelFor(String type) {
  switch (type) {
    case 'CREATE_TREE':
      return 'Tree inventory';
    case 'CREATE_TREE_SUBMISSION':
      return 'Tree submission (pending approval)';
    case 'CREATE_HEALTH_LOG':
      return 'Health log';
    case 'SUBMIT_UNKNOWN':
      return 'Unknown species review';
    case 'CREATE_PLANTING_RECOMMENDATION':
      return 'Planting suggestion';
    default:
      return 'Offline record';
  }
}

IconData _iconFor(String type) {
  switch (type) {
    case 'CREATE_TREE':
      return Icons.forest_outlined;
    case 'CREATE_TREE_SUBMISSION':
      return Icons.how_to_reg_outlined;
    case 'CREATE_HEALTH_LOG':
      return Icons.monitor_heart_outlined;
    case 'SUBMIT_UNKNOWN':
      return Icons.science_outlined;
    case 'CREATE_PLANTING_RECOMMENDATION':
      return Icons.local_florist_outlined;
    default:
      return Icons.cloud_upload_outlined;
  }
}

String _prettyKey(String key) {
  return key
      .replaceAll('_', ' ')
      .split(' ')
      .map((part) =>
          part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}
