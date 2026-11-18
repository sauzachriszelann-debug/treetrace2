import 'package:flutter/material.dart';
import '../services/photo_sources.dart';
import 'expandable_photo.dart';

/// Taxon examples are explicitly separate from the photographed inventory tree.
class SpeciesReferencePhotos extends StatelessWidget {
  const SpeciesReferencePhotos({super.key, required this.photos});
  final List<Map<String, dynamic>> photos;

  @override
  Widget build(BuildContext context) {
    if (photos.isEmpty) return const Text('No verified reference photo is available for this taxon.');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Botanical reference examples, not this individual tree.', style: TextStyle(fontSize: 12)),
      const SizedBox(height: 8),
      SizedBox(height: 205, child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: photos.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, index) {
          final photo = photos[index];
          final asset = photo['asset'];
          final url = photo['url'];
          ImageProvider? image;
          if (asset is String && asset.isNotEmpty) {
            image = AssetImage(asset);
          } else if (url is String && url.startsWith('https://')) {
            image = NetworkImage(url);
          }
          return SizedBox(width: 220, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(12), child: image == null
                ? const Center(child: Text('Photo unavailable'))
                : ExpandablePhoto(image: image, fit: BoxFit.contain, label: photo['caption']?.toString() ?? 'Species reference'))),
            Text(photo['caption']?.toString() ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
          ]));
        },
      )),
      TextButton.icon(icon: const Icon(Icons.copyright_outlined, size: 17),
        label: const Text('Photo credits and sources'),
        onPressed: () => showDialog<void>(context: context, builder: (ctx) => AlertDialog(
          title: const Text('Reference photo credits'),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [for (final photo in photos) Padding(padding: const EdgeInsets.only(bottom: 16),
              child: SelectableText('${photo['caption']}\n${photo['author']} | ${photo['license']}\n${photo['source_url']}\n${photo['license_url']}\nDisplayed to fit; no botanical alterations.'))])),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
        ))),
    ]);
  }
}

class SpeciesComparisons extends StatelessWidget {
  const SpeciesComparisons({super.key, required this.result, this.fallback});
  final Map<String, dynamic> result;
  final String? fallback;

  @override
  Widget build(BuildContext context) {
    final records = speciesComparisons(result);
    if (records.isEmpty) return Text(fallback ?? 'A verified species name is needed before selecting a comparison.');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Botanical comparisons, not additional AI predictions.', style: TextStyle(fontSize: 12)),
      for (final record in records) ...[
        const SizedBox(height: 12),
        Text(record['common_name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        Text(record['scientific_name']?.toString() ?? '', style: const TextStyle(fontStyle: FontStyle.italic)),
        const SizedBox(height: 10),
        SpeciesReferencePhotos(photos: (record['photos'] as List? ?? []).whereType<Map>().map((p) => Map<String, dynamic>.from(p)).toList()),
        const Text('What to compare', style: TextStyle(fontWeight: FontWeight.w600)),
        Text(record['comparison']?.toString() ?? '', style: const TextStyle(height: 1.5)),
        const SizedBox(height: 8),
        SelectableText('Botanical source: ${record['botanical_source'] ?? ''}', style: const TextStyle(fontSize: 12)),
      ],
    ]);
  }
}

/// Also usable by saved profiles that predate persisted scan snapshots.
class SavedSpeciesReferences extends StatelessWidget {
  const SavedSpeciesReferences({super.key, required this.scientificName});
  final String? scientificName;

  @override
  Widget build(BuildContext context) {
    final facts = speciesReferenceFacts(scientificName);
    if (facts.isEmpty) return const SizedBox.shrink();
    final result = {...facts, 'scientific_name': scientificName};
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Species reference information', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        if (facts['family'] != null) Text('Family: ${facts['family']}'),
        const SizedBox(height: 12),
        Text(facts['description']?.toString() ?? ''),
        const SizedBox(height: 12),
        SpeciesReferencePhotos(photos: curatedReferencePhotos(result).map((p) => Map<String, dynamic>.from(p)).toList()),
        SpeciesComparisons(result: result, fallback: facts['look_alikes']?.toString()),
      ],
    )));
  }
}
