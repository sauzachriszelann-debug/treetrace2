import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../services/theme.dart';
import '../widgets/widgets.dart';

class PlantingRecommendationsScreen extends StatefulWidget {
  const PlantingRecommendationsScreen({super.key});

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
      final suggestions = await api.getPlantingSuggestions(
          barangay: _barangayCtrl.text.trim());
      final records =
          await api.getPlantingRecommendations(barangay: _barangayCtrl.text);
      if (!mounted) return;
      setState(() {
        _suggestions = (suggestions['suggestions'] as List? ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _records = records
            .map((e) =>
                PlantingRecommendationModel.fromJson(Map<String, dynamic>.from(e)))
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
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PlantingFormSheet(suggestion: suggestion),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
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
        label: const Text('Add Plant'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
                children: [
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
                          onAdd: () => _openCreateSheet(suggestion: item),
                        )),
                  const SizedBox(height: 20),
                  const _SectionTitle('Planting Requests'),
                  const SizedBox(height: 10),
                  if (_records.isEmpty)
                    const EmptyState(
                      message: 'No planting requests saved yet.',
                      icon: Icons.post_add_rounded,
                    )
                  else
                    ..._records.map((item) => _PlantingRecordCard(item: item)),
                ],
              ),
            ),
    );
  }
}

class _PlantingFormSheet extends StatefulWidget {
  final Map<String, dynamic>? suggestion;
  const _PlantingFormSheet({this.suggestion});

  @override
  State<_PlantingFormSheet> createState() => _PlantingFormSheetState();
}

class _PlantingFormSheetState extends State<_PlantingFormSheet> {
  final _speciesCtrl = TextEditingController();
  final _scientificCtrl = TextEditingController();
  final _barangayCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  File? _photo;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final s = widget.suggestion;
    if (s != null) {
      _speciesCtrl.text = s['species_name']?.toString() ?? '';
      _scientificCtrl.text = s['scientific_name']?.toString() ?? '';
      _reasonCtrl.text = s['reason']?.toString() ?? '';
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
    final x = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 78, maxWidth: 1200);
    if (x != null) setState(() => _photo = File(x.path));
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
      'reason': _reasonCtrl.text.trim().isEmpty ? null : _reasonCtrl.text.trim(),
      'status': 'recommended',
      'planted': false,
    };

    try {
      if (await api.isOnline()) {
        if (_photo != null) payload['photo_url'] = await api.uploadPhoto(_photo!);
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
            ? 'Planting recommendation saved.'
            : 'Saved offline. It will sync when internet returns.'),
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
            const _SectionTitle('Add Planting Recommendation'),
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
            const SizedBox(height: 12),
            TextField(
              controller: _speciesCtrl,
              decoration: const InputDecoration(
                labelText: 'Tree to plant',
                prefixIcon: Icon(Icons.eco_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _scientificCtrl,
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
              label: const Text('Save Recommendation'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onAdd;
  const _SuggestionCard({required this.item, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final priority = item['priority']?.toString() ?? 'Medium';
    final color = priority == 'High' ? kPoor : kFair;
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
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(priority,
                    style: TextStyle(color: color, fontWeight: FontWeight.w900)),
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
          const SizedBox(height: 8),
          Text(
            item['reason']?.toString() ?? '',
            style: const TextStyle(color: kMutedFg, fontSize: 12.5, height: 1.35),
          ),
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
      ),
    );
  }
}

class _PlantingRecordCard extends StatelessWidget {
  final PlantingRecommendationModel item;
  const _PlantingRecordCard({required this.item});

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
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: kPrimary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            clipBehavior: Clip.antiAlias,
            child: item.photoUrl == null
                ? const Icon(Icons.eco_rounded, color: kPrimary)
                : Image.network(item.photoUrl!, fit: BoxFit.cover),
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
                          color: kMutedFg, fontSize: 12, fontStyle: FontStyle.italic)),
                Text(
                  item.barangay ?? item.status,
                  style: const TextStyle(color: kMutedFg, fontSize: 12),
                ),
              ],
            ),
          ),
          HealthBadge(item.planted ? 'Healthy' : 'Fair', small: true),
        ],
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
