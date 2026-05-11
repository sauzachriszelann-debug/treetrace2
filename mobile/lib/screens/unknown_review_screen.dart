import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/theme.dart';

class UnknownReviewScreen extends StatefulWidget {
  const UnknownReviewScreen({super.key});

  @override
  State<UnknownReviewScreen> createState() => _UnknownReviewScreenState();
}

class _UnknownReviewScreenState extends State<UnknownReviewScreen> {
  List<dynamic> _items = [];
  bool _loading = true;
  int? _savingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await api.getUnknownSpeciesReview();
      if (mounted) {
        setState(() {
          _items = data;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _review(dynamic item,
      {required bool reviewed, String? identifiedAs, String? notes}) async {
    final id = item['id'];
    if (id is! int) return;
    setState(() => _savingId = id);
    try {
      await api.reviewUnknownSpecies(id, {
        'reviewed': reviewed,
        'identified_as': identifiedAs,
        'review_notes': notes,
      });
      await _load();
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _savingId = null);
    }
  }

  void _openReviewSheet(dynamic item) {
    final identifiedController = TextEditingController(
      text: '${item['identified_as'] ?? item['possible_name'] ?? ''}',
    );
    final notesController = TextEditingController(
      text: '${item['review_notes'] ?? ''}',
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final reviewed = item['reviewed'] == true;
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: const BoxDecoration(
              color: kCard,
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Review Submission',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w900)),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: identifiedController,
                    decoration: const InputDecoration(
                      labelText: 'Identified as',
                      prefixIcon: Icon(Icons.eco_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: notesController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Review notes',
                      prefixIcon: Icon(Icons.notes_rounded),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _savingId == item['id']
                              ? null
                              : () => _review(
                                    item,
                                    reviewed: true,
                                    identifiedAs: '',
                                    notes: notesController.text.trim(),
                                  ),
                          child: Text(reviewed ? 'Keep Reviewed' : 'Close'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _savingId == item['id']
                              ? null
                              : () => _review(
                                    item,
                                    reviewed: true,
                                    identifiedAs:
                                        identifiedController.text.trim(),
                                    notes: notesController.text.trim(),
                                  ),
                          child: const Text('Approve'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ).whenComplete(() {
      identifiedController.dispose();
      notesController.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final pending = _items.where((e) => e['reviewed'] != true).toList();
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(title: const Text('Unknown Species Review')),
      body: RefreshIndicator(
        onRefresh: _load,
        color: kPrimary,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: kPrimary))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _ReviewSummary(total: _items.length, pending: pending.length),
                  const SizedBox(height: 14),
                  ..._items.map((item) => _ReviewTile(
                        item,
                        onTap: () => _openReviewSheet(item),
                      )),
                  if (_items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 40),
                      child: Center(
                          child: Text('No unknown species submissions.',
                              style: TextStyle(color: kMutedFg))),
                    ),
                ],
              ),
      ),
    );
  }
}

class _ReviewSummary extends StatelessWidget {
  final int total, pending;
  const _ReviewSummary({required this.total, required this.pending});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: pending > 0 ? Colors.orange.shade50 : kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: pending > 0 ? Colors.orange.shade100 : kBorder,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.pending_actions_rounded,
              color: pending > 0 ? Colors.orange.shade800 : kPrimary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '$pending pending review - $total total submissions',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  final dynamic item;
  final VoidCallback onTap;
  const _ReviewTile(this.item, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    final reviewed = item['reviewed'] == true;
    final name = item['possible_name'] ??
        item['identified_as'] ??
        item['common_name'] ??
        'Unknown species';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: reviewed ? kMuted : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                reviewed ? Icons.check_circle_outline : Icons.help_outline,
                color: reviewed ? kHealthy : Colors.orange.shade800,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$name',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900)),
                  Text(reviewed ? 'Reviewed' : 'Needs expert review',
                      style: const TextStyle(color: kMutedFg, fontSize: 11)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: kMutedFg),
          ],
        ),
      ),
    );
  }
}
