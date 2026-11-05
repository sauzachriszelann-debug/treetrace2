import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../services/theme.dart';

/// Admin review queue. In TreeReviewsScreen this is embedded as the second tab;
/// it remains a standalone route for callers that still use it directly.
class UnknownReviewScreen extends StatefulWidget {
  const UnknownReviewScreen(
      {super.key, this.apiOverride, this.embedded = false});

  final ApiService? apiOverride;
  final bool embedded;

  @override
  State<UnknownReviewScreen> createState() => _UnknownReviewScreenState();
}

class _UnknownReviewScreenState extends State<UnknownReviewScreen> {
  late final ApiService _api = widget.apiOverride ?? api;
  List<UnknownSpeciesModel> _items = [];
  String _filter = 'all';
  String? _error;
  bool _loading = true;
  int? _busyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool showSpinner = true}) async {
    if (showSpinner && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final rows = await _api.getUnknownSpeciesReview();
      if (!mounted) return;
      setState(() {
        _items = rows
            .map((row) => UnknownSpeciesModel.fromJson(
                Map<String, dynamic>.from(row as Map)))
            .toList();
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendlyError(error);
      });
    }
  }

  Future<bool> _saveReview(
    UnknownSpeciesModel item, {
    required bool reviewed,
    required String identifiedAs,
    required String notes,
  }) async {
    if (_busyId != null) return false;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busyId = item.id);
    try {
      await _api.reviewUnknownSpecies(item.id, {
        'reviewed': reviewed,
        'identified_as':
            identifiedAs.trim().isEmpty ? null : identifiedAs.trim(),
        'review_notes': notes.trim().isEmpty ? null : notes.trim(),
      });
      if (!mounted) return false;
      messenger.showSnackBar(const SnackBar(content: Text('Review saved.')));
      await _load(showSpinner: false);
      return true;
    } catch (error) {
      if (mounted && messenger.mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text(_friendlyError(error)),
          backgroundColor: kPoor,
        ));
      }
      return false;
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _convert(UnknownSpeciesModel item) async {
    if (_busyId != null) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busyId = item.id);
    try {
      final result = await _api.convertUnknownSpeciesToTreeSubmission(item.id);
      if (!mounted) return;
      final status = result['status']?.toString();
      messenger.showSnackBar(SnackBar(
        content: Text(status == 'pending'
            ? 'Unknown species is available in Tree Submissions. Existing conversions reuse that submission.'
            : 'Unknown species sent to the tree submission review queue.'),
      ));
    } catch (error) {
      if (mounted && messenger.mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text(_friendlyError(error)),
          backgroundColor: kPoor,
        ));
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  void _openDetails(UnknownSpeciesModel item) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _UnknownReviewSheet(
        item: item,
        busy: _busyId == item.id,
        onSave: (reviewed, name, notes) => _saveReview(item,
            reviewed: reviewed, identifiedAs: name, notes: notes),
        onConvert:
            item.reviewStatus == 'identified' ? () => _convert(item) : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _items.where((item) {
      if (_filter == 'all') return true;
      return item.reviewStatus == _filter;
    }).toList();
    final body = RefreshIndicator(
      onRefresh: () => _load(showSpinner: false),
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
                  for (final filter in const [
                    'all',
                    'pending',
                    'identified',
                    'closed'
                  ])
                    _UnknownFilterChip(
                      label: _title(filter),
                      selected: _filter == filter,
                      onSelected: _loading
                          ? null
                          : () => setState(() => _filter = filter),
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
          else if (_error != null)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyState(
                icon: Icons.cloud_off_outlined,
                message: _error!,
                action: 'Try again',
                onAction: _load,
              ),
            )
          else if (visible.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyState(
                icon: Icons.search_off_rounded,
                message: 'No unknown species records in this view.',
                action: 'Refresh',
                onAction: () => _load(showSpinner: false),
              ),
            )
          else ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
              sliver: SliverToBoxAdapter(
                child: Text(
                  '${visible.length} record${visible.length == 1 ? '' : 's'}',
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
                itemCount: visible.length,
                itemBuilder: (_, index) {
                  final item = visible[index];
                  return _UnknownTile(
                    item: item,
                    busy: _busyId == item.id,
                    onTap: () => _openDetails(item),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
    if (widget.embedded) return body;
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(title: const Text('Unknown Species Review')),
      body: body,
    );
  }
}

class _UnknownTile extends StatelessWidget {
  const _UnknownTile(
      {required this.item, required this.busy, required this.onTap});
  final UnknownSpeciesModel item;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = item.identifiedAs?.trim().isNotEmpty == true
        ? item.identifiedAs!
        : item.possibleName?.trim().isNotEmpty == true
            ? item.possibleName!
            : 'Unknown species #${item.id}';
    return Card(
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: .04),
      surfaceTintColor: Colors.transparent,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: busy ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _Photo(url: item.photoUrl, size: 56),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 5,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _UnknownStatusBadge(status: item.reviewStatus),
                        if (item.createdAt != null)
                          Text(_date(item.createdAt),
                              style: const TextStyle(
                                  color: kMutedFg, fontSize: 12)),
                      ],
                    ),
                    if (item.barangay?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 4),
                      Text(item.barangay!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              const TextStyle(color: kMutedFg, fontSize: 12)),
                    ],
                  ],
                ),
              ),
              if (busy) ...[
                const SizedBox(width: 8),
                const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              ] else ...[
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded, color: kMutedFg),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _UnknownFilterChip extends StatelessWidget {
  const _UnknownFilterChip({
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

class _UnknownStatusBadge extends StatelessWidget {
  const _UnknownStatusBadge({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final normalized = status.toLowerCase();
    final (background, foreground) = switch (normalized) {
      'identified' || 'approved' => (
          const Color(0xFFE5F4E9),
          const Color(0xFF17633A)
        ),
      'closed' => (const Color(0xFFE5F4E9), const Color(0xFF17633A)),
      'rejected' => (const Color(0xFFFCE8E8), const Color(0xFFB42318)),
      _ => (const Color(0xFFFFF2D6), const Color(0xFF805000)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _title(status),
        style: TextStyle(
          color: foreground,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _UnknownReviewSheet extends StatefulWidget {
  const _UnknownReviewSheet(
      {required this.item,
      required this.busy,
      required this.onSave,
      this.onConvert});
  final UnknownSpeciesModel item;
  final bool busy;
  final Future<bool> Function(bool reviewed, String name, String notes) onSave;
  final Future<void> Function()? onConvert;

  @override
  State<_UnknownReviewSheet> createState() => _UnknownReviewSheetState();
}

class _UnknownReviewSheetState extends State<_UnknownReviewSheet> {
  late final _name = TextEditingController(
      text: widget.item.identifiedAs ?? widget.item.possibleName ?? '');
  late final _notes =
      TextEditingController(text: widget.item.reviewNotes ?? '');

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .88),
        decoration: const BoxDecoration(
            color: kCard,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                _Photo(url: item.photoUrl, size: 64),
                const SizedBox(width: 12),
                const Expanded(
                    child: Text('Unknown Species Review',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w900))),
                IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded)),
              ]),
              const SizedBox(height: 12),
              _info('Status', _title(item.reviewStatus)),
              _info('Submitted', _date(item.createdAt)),
              _info('Updated', _date(item.updatedAt)),
              _info(
                  'Submitter',
                  [item.submittedByName, item.submittedByEmail]
                      .whereType<String>()
                      .where((v) => v.trim().isNotEmpty)
                      .join(' · ')
                      .ifEmpty('Unavailable')),
              _info('Barangay',
                  item.barangay?.ifEmpty('Not provided') ?? 'Not provided'),
              _info(
                  'Location note',
                  item.locationDescription?.ifEmpty('Not provided') ??
                      'Not provided'),
              _info('Submitter notes',
                  item.submitterNotes?.ifEmpty('None') ?? 'None'),
              if (item.aiCandidates.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('Possible AI matches',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                for (final candidate in item.aiCandidates.take(8))
                  Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(_candidate(candidate))),
              ],
              const SizedBox(height: 14),
              TextField(
                  controller: _name,
                  decoration: const InputDecoration(
                      labelText: 'Identified species (optional when closing)')),
              const SizedBox(height: 10),
              TextField(
                  controller: _notes,
                  minLines: 2,
                  maxLines: 4,
                  decoration:
                      const InputDecoration(labelText: 'Reviewer notes')),
              if (item.reviewNotes?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 8),
                _info('Previous reviewer note', item.reviewNotes!),
              ],
              const SizedBox(height: 12),
              if (widget.busy) const LinearProgressIndicator(minHeight: 2),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton(
                  onPressed: widget.busy
                      ? null
                      : () async {
                          final saved =
                              await widget.onSave(true, '', _notes.text);
                          if (!context.mounted || !saved) return;
                          Navigator.pop(context);
                        },
                  child:
                      Text(item.reviewed ? 'Keep closed' : 'Close unresolved'),
                ),
                ElevatedButton.icon(
                  onPressed: widget.busy || _name.text.trim().isEmpty
                      ? null
                      : () async {
                          final saved = await widget.onSave(
                              true, _name.text, _notes.text);
                          if (!context.mounted || !saved) return;
                          Navigator.pop(context);
                        },
                  icon: const Icon(Icons.check),
                  label: const Text('Approve identification'),
                ),
                if (item.reviewed)
                  TextButton(
                      onPressed: widget.busy
                          ? null
                          : () async {
                              final saved = await widget.onSave(
                                  false, _name.text, _notes.text);
                              if (!context.mounted || !saved) return;
                              Navigator.pop(context);
                            },
                      child: const Text('Reopen')),
                if (widget.onConvert != null)
                  OutlinedButton.icon(
                    onPressed: widget.busy
                        ? null
                        : () async {
                            final confirm = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                      title:
                                          const Text('Send to tree reviews?'),
                                      content: const Text(
                                          'Create or reuse a pending tree submission from this identified species.'),
                                      actions: [
                                        TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, false),
                                            child: const Text('Cancel')),
                                        ElevatedButton(
                                            onPressed: () =>
                                                Navigator.pop(context, true),
                                            child: const Text('Continue')),
                                      ],
                                    ));
                            if (!context.mounted || confirm != true) return;
                            await widget.onConvert!();
                          },
                    icon: const Icon(Icons.playlist_add),
                    label: const Text('Send to Tree Submissions'),
                  ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Photo extends StatelessWidget {
  const _Photo({required this.url, required this.size});
  final String? url;
  final double size;
  @override
  Widget build(BuildContext context) {
    final usable = url?.trim().isNotEmpty == true;
    return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: usable
            ? Image.network(url!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _fallback())
            : _fallback());
  }

  Widget _fallback() => Container(
      width: size,
      height: size,
      color: kPrimary.withValues(alpha: .08),
      child: const Icon(Icons.eco_outlined, color: kPrimary));
}

class _EmptyState extends StatelessWidget {
  const _EmptyState(
      {required this.icon, required this.message, this.action, this.onAction});
  final IconData icon;
  final String message;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 42, color: kMutedFg),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        if (action != null) ...[
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: onAction,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(action!),
          )
        ],
      ]));
}

Widget _info(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Text('$label: $value', style: const TextStyle(fontSize: 13)));

String _candidate(dynamic value) {
  if (value is! Map) return value.toString();
  final fields = [
    value['common_name'] ?? value['name'],
    value['scientific_name']
  ]
      .whereType<Object>()
      .map((v) => v.toString())
      .where((v) => v.trim().isNotEmpty)
      .toList();
  final confidence =
      value['confidence_percent'] ?? value['confidence'] ?? value['score'];
  if (confidence is num) {
    fields.add(
        '${(confidence > 1 ? confidence : confidence * 100).toStringAsFixed(1)}%');
  }
  return fields.isEmpty
      ? 'Candidate information unavailable'
      : fields.join(' · ');
}

String _title(String value) =>
    value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';
String _date(DateTime? value) => value == null
    ? 'Date unavailable'
    : DateFormat.yMMMMd().format(value.toLocal());
String _friendlyError(Object error) {
  if (error is DioException) {
    if (error.response?.statusCode == 403) {
      return 'Your account is not allowed to review unknown species.';
    }
    final detail = error.response?.data;
    if (detail is Map && detail['detail'] is String) {
      return detail['detail'] as String;
    }
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return 'Cannot reach TreeTrace. Check your connection and try again.';
    }
  }
  return 'Could not load or save unknown species reviews. Try again.';
}

extension on String {
  String ifEmpty(String fallback) => trim().isEmpty ? fallback : this;
}
