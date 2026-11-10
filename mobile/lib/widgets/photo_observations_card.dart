import 'package:flutter/material.dart';

class PhotoObservationsCard extends StatelessWidget {
  final Map<String, dynamic>? observations;
  const PhotoObservationsCard({super.key, this.observations});

  static const signs = {
    'leaf_discoloration': 'Leaf discoloration',
    'leaf_spots': 'Spots visible on leaves',
    'leaf_holes': 'Holes visible in leaves',
    'trunk_wound': 'Visible trunk wound',
    'dead_branches': 'Apparently dead branches',
    'fungal_growth': 'Fungal-like growth visible',
    'sap_flow': 'Sap-like fluid visible',
  };

  @override
  Widget build(BuildContext context) {
    final assessed = observations?['status'] == 'observed';
    final raw = observations?['visible_signs'];
    final items = raw is List
        ? raw
            .whereType<Map>()
            .where((s) => signs.containsKey(s['code']))
            .toList()
        : <Map>[];
    final bark = observations?['bark_appearance'];
    final barkLabel =
        assessed && ['Smooth', 'Rough', 'Ridged', 'Flaky'].contains(bark)
            ? bark
            : 'Unclear';
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Visible appearance — AI observations',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Text('Bark appearance: $barkLabel'),
                if (assessed &&
                    observations?['bark_evidence'] is String &&
                    observations!['bark_evidence'].isNotEmpty)
                  Text(observations!['bark_evidence'] as String),
                const SizedBox(height: 8),
                const Text('Visible signs of damage or stress'),
                if (!assessed) const Text('Not assessed from this photo.'),
                for (final item in items)
                  Text('${signs[item['code']]}: ${item['evidence'] ?? ''}'),
                if (assessed && items.isEmpty)
                  Text(observations?['no_visible_signs'] == true
                      ? 'No visible symptoms in the parts shown. This does not establish that the tree is healthy.'
                      : 'No supported observation reported. This does not establish that symptoms are absent.'),
                if (observations?['needs_closeup'] != false)
                  const Text(
                      'For more detail, add a closer bark, leaf or affected-area photo.'),
                const SizedBox(height: 8),
                const Text(
                    'Unvalidated photo observations, not a disease diagnosis. Health status requires field review.'),
              ],
            )));
  }
}
