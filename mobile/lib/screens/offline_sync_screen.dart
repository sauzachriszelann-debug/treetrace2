import 'dart:io';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/theme.dart';
import '../widgets/widgets.dart';

class OfflineSyncScreen extends StatefulWidget {
  const OfflineSyncScreen({super.key});

  @override
  State<OfflineSyncScreen> createState() => _OfflineSyncScreenState();
}

class _OfflineSyncScreenState extends State<OfflineSyncScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await api.offlineQueue();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _setVerified(Map<String, dynamic> item, bool value) async {
    final id = item['id'];
    if (id is! int) return;
    await api.setOfflineActionVerified(id, value);
    await _load();
  }

  Future<void> _verifyAll() async {
    await api.verifyAllOfflineActions();
    await _load();
  }

  Future<void> _deleteItem(Map<String, dynamic> item) async {
    final id = item['id'];
    if (id is! int) return;
    await api.deleteOfflineAction(id);
    await _load();
  }

  Future<void> _syncVerified() async {
    setState(() => _syncing = true);
    final synced = await api.syncOfflineQueue();
    await _load();
    if (!mounted) return;
    setState(() => _syncing = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(synced > 0
          ? 'Synced $synced verified item${synced == 1 ? '' : 's'}.'
          : 'No verified offline items synced.'),
      backgroundColor: synced > 0 ? kHealthy : kMutedFg,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final verifiedCount = _items.where((item) => item['verified'] == true).length;
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
                  _SyncSummary(
                    total: _items.length,
                    verified: verifiedCount,
                    onVerifyAll: _items.isEmpty ? null : _verifyAll,
                    onSync: verifiedCount == 0 || _syncing ? null : _syncVerified,
                    syncing: _syncing,
                  ),
                  const SizedBox(height: 14),
                  if (_items.isEmpty)
                    const EmptyState(
                      message: 'No offline records waiting for sync.',
                      subtitle: 'New offline trees, unknown species, and planting suggestions will appear here for review.',
                      icon: Icons.cloud_done_outlined,
                    )
                  else
                    ..._items.map((item) => _OfflineQueueCard(
                          item: item,
                          onChanged: (value) => _setVerified(item, value),
                          onDelete: () => _deleteItem(item),
                        )),
                ],
              ),
            ),
    );
  }
}

class _SyncSummary extends StatelessWidget {
  final int total;
  final int verified;
  final VoidCallback? onVerifyAll;
  final VoidCallback? onSync;
  final bool syncing;

  const _SyncSummary({
    required this.total,
    required this.verified,
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
                  '$verified of $total verified',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Review each offline record before uploading. Only verified items will sync.',
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

class _OfflineQueueCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final ValueChanged<bool> onChanged;
  final VoidCallback onDelete;

  const _OfflineQueueCard({
    required this.item,
    required this.onChanged,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final payload = Map<String, dynamic>.from(item['payload'] ?? {});
    final type = item['type']?.toString() ?? 'OFFLINE_RECORD';
    final verified = item['verified'] == true;
    final photoPath = item['photo_path']?.toString() ?? '';
    final createdAt = DateTime.tryParse(item['created_at']?.toString() ?? '');
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: verified ? kHealthy.withOpacity(0.35) : kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _OfflinePhoto(path: photoPath, type: type),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _titleFor(type, payload),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _labelFor(type),
                      style: const TextStyle(
                        color: kPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                    if (createdAt != null)
                      Text(
                        '${createdAt.month}/${createdAt.day}/${createdAt.year} ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(color: kMutedFg, fontSize: 10.5),
                      ),
                  ],
                ),
              ),
              Switch(
                value: verified,
                activeColor: kHealthy,
                onChanged: onChanged,
              ),
            ],
          ),
          const SizedBox(height: 10),
          _PayloadPreview(payload: payload),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  verified ? 'Verified for sync' : 'Needs your verification',
                  style: TextStyle(
                    color: verified ? kHealthy : kFair,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
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
}

class _PayloadPreview extends StatelessWidget {
  final Map<String, dynamic> payload;
  const _PayloadPreview({required this.payload});

  @override
  Widget build(BuildContext context) {
    final rows = payload.entries
        .where((entry) => entry.value != null && entry.value.toString().trim().isNotEmpty)
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
  final String path;
  final String type;
  const _OfflinePhoto({required this.path, required this.type});

  @override
  Widget build(BuildContext context) {
    final file = path.isNotEmpty ? File(path) : null;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: file != null && file.existsSync()
          ? Image.file(file, width: 58, height: 58, fit: BoxFit.cover)
          : Container(
              width: 58,
              height: 58,
              color: kPrimary.withOpacity(0.08),
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
    case 'SUBMIT_UNKNOWN':
      return Icons.science_outlined;
    case 'CREATE_PLANTING_RECOMMENDATION':
      return Icons.add_location_alt_outlined;
    default:
      return Icons.cloud_upload_outlined;
  }
}

String _prettyKey(String key) {
  return key
      .replaceAll('_', ' ')
      .split(' ')
      .map((part) => part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}
