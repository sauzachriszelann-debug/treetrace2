import 'package:flutter/material.dart';
import '../screens/tree_detail_screen.dart';
import 'expandable_photo.dart';

Future<bool> showNearbyTreeWarnings(BuildContext context,
    List<Map<String, dynamic>> candidates, {bool preview = false}) async {
    final proceed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * 0.82,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: Text(preview ? 'Duplicate warning preview' : 'Check nearby trees',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
                IconButton(tooltip: 'Close', icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(sheetContext, false)),
              ]),
              Text(preview ? 'Sample data only. Nothing will be saved.' : 'Compare the photos before adding a new tree. Nearby pins can represent different trees.',
                  style: TextStyle(fontSize: 14, height: 1.4)),
              const SizedBox(height: 16),
              Expanded(child: ListView.separated(
                itemCount: candidates.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, index) {
                  final candidate = candidates[index];
                  final distance = (candidate['distance_m'] as num?)?.toDouble();
                  final photo = candidate['photo_url'];
                  final species = candidate['scientific_name']?.toString() ?? '';
                  final match = candidate['species_match'];
                  final warningColor = candidate['duplicate_warning'] == 'red' ? Colors.red : Colors.amber;
                  final note = candidate['accuracy_overlap'] == true
                      ? 'GPS accuracy areas overlap'
                      : candidate['accuracy_incomplete'] == true
                          ? 'Older GPS accuracy unavailable'
                          : 'Nearby location';
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: warningColor.withValues(alpha: 0.08), border: Border.all(color: warningColor),
                        borderRadius: BorderRadius.circular(16)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        ClipRRect(borderRadius: BorderRadius.circular(10),
                          child: SizedBox(width: 80, height: 96,
                            child: photo is String && photo.startsWith('https://')
                              ? ExpandablePhoto(image: NetworkImage(photo), label: 'Existing tree', width: 80, height: 96)
                              : const Icon(Icons.park_outlined, size: 40))),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(candidate['common_name']?.toString() ?? 'Unnamed tree',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                          if (species.isNotEmpty) Text(species,
                            style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic)),
                          const SizedBox(height: 6),
                          Text(distance == null ? 'Distance unavailable' : '~${distance.round()} m away',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          if (candidate['barangay'] != null) Text(candidate['barangay'].toString(),
                            style: const TextStyle(fontSize: 13)),
                        ])),
                      ]),
                      const SizedBox(height: 10),
                      if (candidate['duplicate_reason'] != null) Text(candidate['duplicate_reason'].toString(), style: TextStyle(color: warningColor, fontWeight: FontWeight.w600)),
                      Text('${match == 'exact' ? 'Same species' : match == 'different' ? 'Different species' : 'Species not provided'} · $note',
                        style: const TextStyle(fontSize: 12, height: 1.4)),
                      Align(alignment: Alignment.centerRight, child: TextButton.icon(
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: const Text('View tree record'),
                        onPressed: preview || candidate['tree_id'] is! int ? null : () => Navigator.push(
                          sheetContext, MaterialPageRoute(builder: (_) => TreeDetailScreen(treeId: candidate['tree_id']))),
                      )),
                    ]),
                  );
                },
              )),
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, child: ElevatedButton(
                onPressed: () => Navigator.pop(sheetContext, true),
                child: const Text('Different tree — continue'))),
              SizedBox(width: double.infinity, child: TextButton(
                onPressed: () => Navigator.pop(sheetContext, false),
                child: Text(preview ? 'Close preview' : 'Back to form'))),
            ],
          ),
        ),
      ),
    );
    return proceed == true;
  }

