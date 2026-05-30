import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../services/auth_provider.dart';
import '../services/theme.dart';
import '../widgets/widgets.dart';

class PlantingRecommendationsScreen extends StatefulWidget {
  final bool focusReview;
  const PlantingRecommendationsScreen({super.key, this.focusReview = false});

  @override
  State<PlantingRecommendationsScreen> createState() =>
      _PlantingRecommendationsScreenState();
}

class _PlantingRecommendationsScreenState
    extends State<PlantingRecommendationsScreen> {
  final _barangayCtrl = TextEditingController();
  List<Map<String, dynamic>> _suggestions = [];
  List<PlantingRecommendationModel> _records = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _barangayCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final suggestions =
          await api.getPlantingSuggestions(barangay: _barangayCtrl.text.trim());
      final records =
          await api.getPlantingRecommendations(barangay: _barangayCtrl.text);
      if (!mounted) return;
      setState(() {
        _suggestions = (suggestions['suggestions'] as List? ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _records = records
            .map((e) => PlantingRecommendationModel.fromJson(
                Map<String, dynamic>.from(e)))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Could not load planting planner.'),
        backgroundColor: kPoor,
      ));
    }
  }

  Future<void> _openCreateSheet({Map<String, dynamic>? suggestion}) async {
    final user = context.read<AuthProvider>().user;
    final isManager = user?.role == 'admin' || user?.role == 'field_worker';
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PlantingFormSheet(
        suggestion: suggestion,
        isManager: isManager,
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _reviewRequest(
      PlantingRecommendationModel item, bool approved) async {
    final noteCtrl = TextEditingController();
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReviewDecisionSheet(
        approved: approved,
        controller: noteCtrl,
      ),
    );
    if (saved != true) {
      noteCtrl.dispose();
      return;
    }
    final note = noteCtrl.text.trim();
    noteCtrl.dispose();
    if (!approved && note.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please add a reason before rejecting.'),
        backgroundColor: kPoor,
      ));
      return;
    }
    final existingReason = item.reason?.trim() ?? '';
    final decision = approved ? 'Approved' : 'Rejected';
    final reason = [
      if (existingReason.isNotEmpty) existingReason,
      '$decision by admin/field: ${note.isEmpty ? (approved ? 'Suitable for planting.' : 'Not suitable for the selected area.') : note}',
    ].join('\n\n');
    try {
      await api.updatePlantingRecommendation(item.id, {
        'status': approved ? 'approved' : 'rejected',
        'reason': reason,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(approved
            ? 'Plant suggestion approved and moved to suggestions.'
            : 'Plant suggestion rejected with reason.'),
        backgroundColor: approved ? kHealthy : kPoor,
      ));
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not review suggestion: $e'),
        backgroundColor: kPoor,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final isManager = user?.role == 'admin' || user?.role == 'field_worker';
    final pendingRecords =
        _records.where((item) => item.status == 'pending').toList();
    final visibleRecords = isManager
        ? _records.where((item) => item.status != 'pending').toList()
        : _records.where((item) => item.status != 'approved').toList();
    final showReviewFirst = widget.focusReview && isManager;
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        title: const Text('Planting Recommendations'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openCreateSheet(),
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: Text(isManager ? 'Add Plant' : 'Suggest Plant'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
                children: [
                  if (showReviewFirst && pendingRecords.isNotEmpty) ...[
                    const _SectionTitle('Citizen Suggestions for Review'),
                    const SizedBox(height: 10),
                    ...pendingRecords.map((item) => _PlantingRecordCard(
                          item: item,
                          isManager: true,
                          onApprove: () => _reviewRequest(item, true),
                          onReject: () => _reviewRequest(item, false),
                        )),
                    const SizedBox(height: 20),
                  ],
                  if (!showReviewFirst) ...[
                    TextField(
                      controller: _barangayCtrl,
                      decoration: InputDecoration(
                        labelText: 'Focus barangay',
                        hintText: 'Optional, e.g. Brgy. San Francisco',
                        prefixIcon: const Icon(Icons.location_on_outlined),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.search_rounded),
                          onPressed: _load,
                        ),
                      ),
                      onSubmitted: (_) => _load(),
                    ),
                    const SizedBox(height: 16),
                    _AddPlantPrompt(
                      isManager: isManager,
                      onTap: () => _openCreateSheet(),
                    ),
                    const SizedBox(height: 16),
                    const _SectionTitle('Suggested Trees to Plant'),
                    const SizedBox(height: 10),
                    if (_suggestions.isEmpty)
                      const EmptyState(
                        message: 'No planting suggestions yet.',
                        icon: Icons.eco_outlined,
                      )
                    else
                      ..._suggestions.map((item) => _SuggestionCard(
                            item: item,
                            canAdd: isManager,
                            onAdd: () => _openCreateSheet(suggestion: item),
                          )),
                    if (isManager && pendingRecords.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      const _SectionTitle('Citizen Suggestions for Review'),
                      const SizedBox(height: 10),
                      ...pendingRecords.map((item) => _PlantingRecordCard(
                            item: item,
                            isManager: true,
                            onApprove: () => _reviewRequest(item, true),
                            onReject: () => _reviewRequest(item, false),
                          )),
                    ],
                  ] else if (pendingRecords.isEmpty) ...[
                    const EmptyState(
                      message: 'No suggested plants waiting for review.',
                      icon: Icons.task_alt_rounded,
                    ),
                  ],
                  const SizedBox(height: 20),
                  _SectionTitle(
                      isManager ? 'Planting Records' : 'My Suggested Plants'),
                  const SizedBox(height: 10),
                  if (visibleRecords.isEmpty)
                    EmptyState(
                      message: isManager
                          ? 'No planting records saved yet.'
                          : 'No plant suggestions submitted yet.',
                      icon: Icons.post_add_rounded,
                    )
                  else
                    ...visibleRecords.map((item) => _PlantingRecordCard(
                          item: item,
                          isManager: isManager,
                          onApprove: item.status == 'pending'
                              ? () => _reviewRequest(item, true)
                              : null,
                          onReject: item.status == 'pending'
                              ? () => _reviewRequest(item, false)
                              : null,
                        )),
                ],
              ),
            ),
    );
  }
}

class _PlantingFormSheet extends StatefulWidget {
  final Map<String, dynamic>? suggestion;
  final bool isManager;
  const _PlantingFormSheet({this.suggestion, required this.isManager});

  @override
  State<_PlantingFormSheet> createState() => _PlantingFormSheetState();
}

class _PlantingFormSheetState extends State<_PlantingFormSheet> {
  final _speciesCtrl = TextEditingController();
  final _scientificCtrl = TextEditingController();
  final _barangayCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  File? _photo;
  List<String> _similarPhotos = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final s = widget.suggestion;
    if (s != null) {
      _speciesCtrl.text = s['species_name']?.toString() ?? '';
      _scientificCtrl.text = s['scientific_name']?.toString() ?? '';
      _barangayCtrl.text = s['recommended_area']?.toString() ?? '';
      _reasonCtrl.text = s['reason']?.toString() ?? '';
      _similarPhotos = _imageUrlsFor(s);
    }
  }

  @override
  void dispose() {
    _speciesCtrl.dispose();
    _scientificCtrl.dispose();
    _barangayCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final x = await ImagePicker().pickImage(
        source: ImageSource.gallery, imageQuality: 78, maxWidth: 1200);
    if (x != null) {
      setState(() {
        _photo = File(x.path);
        _similarPhotos = _imageUrlsFor({
          'species_name': _speciesCtrl.text.trim().isEmpty
              ? 'tree seedling'
              : _speciesCtrl.text.trim(),
          'scientific_name': _scientificCtrl.text.trim(),
        });
      });
    }
  }

  Future<void> _save() async {
    if (_speciesCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    final payload = <String, dynamic>{
      'species_name': _speciesCtrl.text.trim(),
      'scientific_name': _scientificCtrl.text.trim().isEmpty
          ? null
          : _scientificCtrl.text.trim(),
      'barangay':
          _barangayCtrl.text.trim().isEmpty ? null : _barangayCtrl.text.trim(),
      'reason':
          _reasonCtrl.text.trim().isEmpty ? null : _reasonCtrl.text.trim(),
      'status': widget.isManager ? 'recommended' : 'pending',
      'planted': false,
    };

    try {
      if (await api.isOnline()) {
        if (_photo != null)
          payload['photo_url'] = await api.uploadPhoto(_photo!);
        await api.createPlantingRecommendation(payload);
      } else {
        await api.queueOfflineAction(
          'CREATE_PLANTING_RECOMMENDATION',
          payload,
          photoPath: _photo?.path,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(await api.isOnline()
            ? (widget.isManager
                ? 'Planting recommendation saved.'
                : 'Suggestion sent for admin review.')
            : 'Saved offline. Review it in Field Sync before uploading.'),
        backgroundColor: kHealthy,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not save: $e'),
        backgroundColor: kPoor,
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.82,
      maxChildSize: 0.95,
      minChildSize: 0.45,
      builder: (_, controller) => Container(
        padding: EdgeInsets.fromLTRB(
          18,
          14,
          18,
          MediaQuery.of(context).viewInsets.bottom + 18,
        ),
        decoration: const BoxDecoration(
          color: kBackground,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: ListView(
          controller: controller,
          children: [
            _SectionTitle(widget.isManager
                ? 'Add Planting Recommendation'
                : 'Suggest Plant for This Area'),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: _pickPhoto,
              child: Container(
                height: 140,
                decoration: BoxDecoration(
                  color: kCard,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: kBorder),
                ),
                clipBehavior: Clip.antiAlias,
                child: _photo == null
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_photo_alternate_outlined,
                                color: kMutedFg, size: 34),
                            SizedBox(height: 8),
                            Text('Add tree/seedling photo',
                                style: TextStyle(color: kMutedFg)),
                          ],
                        ),
                      )
                    : Image.file(_photo!, fit: BoxFit.cover),
              ),
            ),
            if (_similarPhotos.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Similar photos / seedlings',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              _PhotoStrip(
                urls: _similarPhotos,
                title: _speciesCtrl.text.trim().isEmpty
                    ? 'Tree seedling'
                    : _speciesCtrl.text.trim(),
                subtitle: _barangayCtrl.text.trim(),
                description: _reasonCtrl.text.trim().isEmpty
                    ? 'Similar tree or seedling reference photo.'
                    : _reasonCtrl.text.trim(),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _speciesCtrl,
              onChanged: (_) => setState(() {
                _similarPhotos = _imageUrlsFor({
                  'species_name': _speciesCtrl.text.trim(),
                  'scientific_name': _scientificCtrl.text.trim(),
                });
              }),
              decoration: const InputDecoration(
                labelText: 'Tree to plant',
                prefixIcon: Icon(Icons.eco_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _scientificCtrl,
              onChanged: (_) => setState(() {
                _similarPhotos = _imageUrlsFor({
                  'species_name': _speciesCtrl.text.trim(),
                  'scientific_name': _scientificCtrl.text.trim(),
                });
              }),
              decoration: const InputDecoration(
                labelText: 'Scientific name',
                prefixIcon: Icon(Icons.science_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _barangayCtrl,
              decoration: const InputDecoration(
                labelText: 'Barangay / area',
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _reasonCtrl,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Reason',
                prefixIcon: Icon(Icons.notes_outlined),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(widget.isManager
                  ? 'Save Recommendation'
                  : 'Submit for Review'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddPlantPrompt extends StatelessWidget {
  final bool isManager;
  final VoidCallback onTap;
  const _AddPlantPrompt({required this.isManager, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: kSidebarBg,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: kSidebarBg.withOpacity(0.12),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(Icons.add_circle_outline_rounded,
                  color: kSidebarPrimary, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isManager
                      ? 'Add official planting suggestion'
                      : 'Add user suggested plant for this area',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: kSidebarPrimary),
            ],
          ),
        ),
      ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final bool canAdd;
  final VoidCallback onAdd;
  const _SuggestionCard({
    required this.item,
    required this.canAdd,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final priority = item['priority']?.toString() ?? 'Medium';
    final color = priority == 'High' ? kPoor : kFair;
    final images = _imageUrlsFor(item);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item['species_name']?.toString() ?? 'Suggested tree',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w900),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(priority,
                    style:
                        TextStyle(color: color, fontWeight: FontWeight.w900)),
              ),
            ],
          ),
          if ((item['scientific_name'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              item['scientific_name'].toString(),
              style: const TextStyle(
                  color: kMutedFg, fontStyle: FontStyle.italic, fontSize: 12),
            ),
          ],
          if (images.isNotEmpty) ...[
            const SizedBox(height: 10),
            _PhotoStrip(
              urls: images,
              title: item['species_name']?.toString() ?? 'Suggested tree',
              subtitle: item['recommended_area']?.toString() ??
                  item['scientific_name']?.toString() ??
                  '',
              description: item['area_reason']?.toString() ??
                  item['reason']?.toString() ??
                  'Recommended planting suggestion.',
            ),
          ],
          const SizedBox(height: 8),
          Text(
            item['reason']?.toString() ?? '',
            style:
                const TextStyle(color: kMutedFg, fontSize: 12.5, height: 1.35),
          ),
          const SizedBox(height: 8),
          _AreaReason(
            area: item['recommended_area']?.toString(),
            reason: item['area_reason']?.toString(),
          ),
          if (canAdd) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_location_alt_outlined, size: 16),
                label: const Text('Add Plant'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PhotoStrip extends StatelessWidget {
  final List<String> urls;
  final String title;
  final String? subtitle;
  final String? description;
  const _PhotoStrip({
    required this.urls,
    required this.title,
    this.subtitle,
    this.description,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 86,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: urls.take(5).length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, index) {
          final url = urls[index];
          return InkWell(
            onTap: () => _showPlantPhotoDetail(
              context,
              imageUrls: urls,
              initialIndex: index,
              title: title,
              subtitle: subtitle,
              description: description,
            ),
            borderRadius: BorderRadius.circular(14),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.network(
                url,
                width: 108,
                height: 86,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 108,
                  height: 86,
                  color: kPrimary.withOpacity(0.08),
                  child: const Icon(Icons.eco_outlined, color: kPrimary),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AreaReason extends StatelessWidget {
  final String? area;
  final String? reason;
  const _AreaReason({this.area, this.reason});

  @override
  Widget build(BuildContext context) {
    if ((area ?? '').isEmpty && (reason ?? '').isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: kBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if ((area ?? '').isNotEmpty)
            Row(
              children: [
                const Icon(Icons.place_outlined, size: 15, color: kPrimary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    area!,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          if ((reason ?? '').isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              reason!,
              style: const TextStyle(
                color: kMutedFg,
                fontSize: 11.5,
                height: 1.3,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

List<String> _imageUrlsFor(Map<String, dynamic> item) {
  final photoUrl = (item['photo_url'] ?? item['photoUrl'] ?? '')
      .toString()
      .trim();
  final provided = item['image_urls'];
  if (provided is List) {
    final urls = [
      if (photoUrl.isNotEmpty && photoUrl != 'null') photoUrl,
      ...provided.map((e) => e.toString()),
    ]
        .where((e) => e.trim().isNotEmpty)
        .where((e) => e != 'null')
        .toList();
    if (urls.isNotEmpty) return urls;
  }
  final name = (item['species_name'] ?? item['common_name'] ?? 'tree seedling')
      .toString()
      .trim();
  final scientific = (item['scientific_name'] ?? '').toString().trim();
  final terms = [
    name,
    if (scientific.isNotEmpty) scientific,
    '$name seedling',
    '$name leaves',
    '$name seeds',
  ];
  final generated = terms
      .map((term) =>
          'https://tse1.mm.bing.net/th?q=${Uri.encodeComponent('$term tree')}')
      .toList();
  return [
    if (photoUrl.isNotEmpty && photoUrl != 'null') photoUrl,
    ...generated,
  ];
}

class _PlantingRecordCard extends StatelessWidget {
  final PlantingRecommendationModel item;
  final bool isManager;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  const _PlantingRecordCard({
    required this.item,
    required this.isManager,
    this.onApprove,
    this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: kPrimary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _showPlantPhotoDetail(
                    context,
                    imageUrls: [
                      if ((item.photoUrl ?? '').isNotEmpty) item.photoUrl!,
                      ..._imageUrlsFor({
                        'species_name': item.speciesName,
                        'scientific_name': item.scientificName ?? '',
                      }),
                    ],
                    title: item.speciesName,
                    subtitle: item.barangay ?? item.scientificName,
                    description: item.reason,
                  ),
                  child: item.photoUrl == null
                      ? const Icon(Icons.eco_rounded, color: kPrimary)
                      : Image.network(item.photoUrl!, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.speciesName,
                        style: const TextStyle(fontWeight: FontWeight.w900)),
                    if ((item.scientificName ?? '').isNotEmpty)
                      Text(item.scientificName!,
                          style: const TextStyle(
                              color: kMutedFg,
                              fontSize: 12,
                              fontStyle: FontStyle.italic)),
                    Text(
                      item.barangay ?? 'No area selected',
                      style: const TextStyle(color: kMutedFg, fontSize: 12),
                    ),
                  ],
                ),
              ),
              _StatusChip(item.status),
            ],
          ),
          if ((item.reason ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              item.reason!,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: kMutedFg,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
          if (isManager && item.status == 'pending') ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onReject,
                    icon: const Icon(Icons.close_rounded, size: 16),
                    label: const Text('Reject'),
                    style: OutlinedButton.styleFrom(foregroundColor: kPoor),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onApprove,
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: const Text('Approve'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip(this.status);

  @override
  Widget build(BuildContext context) {
    final normalized = status.toLowerCase();
    final color = normalized == 'approved' || normalized == 'recommended'
        ? kHealthy
        : normalized == 'rejected'
            ? kPoor
            : kFair;
    final label = normalized == 'recommended'
        ? 'Official'
        : normalized == 'approved'
            ? 'Approved'
            : normalized == 'rejected'
                ? 'Rejected'
                : 'Pending';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

void _showPlantPhotoDetail(
  BuildContext context, {
  required List<String> imageUrls,
  int initialIndex = 0,
  required String title,
  String? subtitle,
  String? description,
}) {
  final urls = imageUrls.where((url) => url.trim().isNotEmpty).toList();
  final pageController = PageController(
    initialPage: urls.isEmpty ? 0 : initialIndex.clamp(0, urls.length - 1),
  );
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.42,
      maxChildSize: 0.94,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: kBackground,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            if ((subtitle ?? '').isNotEmpty)
              Text(
                subtitle!,
                style: const TextStyle(
                  color: kPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            const SizedBox(height: 12),
            SizedBox(
              height: 270,
              child: urls.isEmpty
                  ? _PlantPhotoFallback(height: 270)
                  : PageView.builder(
                      controller: pageController,
                      itemCount: urls.length,
                      itemBuilder: (_, index) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Image.network(
                            urls[index],
                            height: 270,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const _PlantPhotoFallback(height: 270),
                          ),
                        ),
                      ),
                    ),
            ),
            if (urls.length > 1) ...[
              const SizedBox(height: 8),
              const Center(
                child: Text(
                  'Swipe photos',
                  style: TextStyle(color: kMutedFg, fontSize: 12),
                ),
              ),
            ],
            const SizedBox(height: 14),
            Text(
              (description ?? '').trim().isEmpty
                  ? 'No description added yet.'
                  : description!.trim(),
              style: const TextStyle(
                color: kForeground,
                fontSize: 14,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _PlantPhotoFallback extends StatelessWidget {
  final double height;
  const _PlantPhotoFallback({required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      color: kPrimary.withOpacity(0.08),
      child: const Icon(
        Icons.eco_outlined,
        color: kPrimary,
        size: 48,
      ),
    );
  }
}

class _ReviewDecisionSheet extends StatelessWidget {
  final bool approved;
  final TextEditingController controller;
  const _ReviewDecisionSheet({
    required this.approved,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: const BoxDecoration(
          color: kBackground,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                approved
                    ? 'Approve Plant Suggestion'
                    : 'Reject Plant Suggestion',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: controller,
                minLines: 3,
                maxLines: 5,
                decoration: InputDecoration(
                  labelText: approved
                      ? 'Why is this needed in the area?'
                      : 'Why is this not approved?',
                  prefixIcon: const Icon(Icons.notes_outlined),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context, true),
                  icon: Icon(
                    approved ? Icons.check_rounded : Icons.close_rounded,
                  ),
                  label: Text(approved ? 'Approve' : 'Reject'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: approved ? kPrimary : kPoor,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: kForeground,
        fontSize: 18,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}
