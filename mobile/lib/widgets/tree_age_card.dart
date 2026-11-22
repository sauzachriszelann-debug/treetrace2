import '../models/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';

import '../services/api_service.dart';
import '../services/photo_sources.dart';
import 'species_references.dart';

typedef AgeLookup = Future<Map<String, dynamic>> Function(
    String species, double? dbh, double? height, String source);

/// Display only. Never writes age, dates or predicted sizes to inventory.
class TreeAgeCard extends StatefulWidget {
  final String scientificName;
  final double? dbhCm;
  final double? heightM;
  final String dimensionsSource;
  final AgeLookup? lookup;
  final ValueChanged<Map<String, dynamic>>? onEstimated;
  final Map<String, dynamic>? initialEstimate;
  const TreeAgeCard(
      {super.key,
      required this.scientificName,
      this.dbhCm,
      this.heightM,
      this.dimensionsSource = 'ai_prediction',
      this.lookup, this.onEstimated, this.initialEstimate});

  @override
  State<TreeAgeCard> createState() => _TreeAgeCardState();
}

class _TreeAgeCardState extends State<TreeAgeCard> {
  Map<String, dynamic>? _result;
  bool _loading = false;
  bool _failed = false;
  String _failureMessage = 'Age estimate unavailable. Check your connection.';
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant TreeAgeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scientificName != widget.scientificName ||
        oldWidget.dbhCm != widget.dbhCm ||
        oldWidget.heightM != widget.heightM ||
        oldWidget.dimensionsSource != widget.dimensionsSource ||
        oldWidget.initialEstimate != widget.initialEstimate) {
      _load();
    }
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _failed = false;
      _result = null;
    });
    try {
      final result = widget.initialEstimate ?? await (widget.lookup ?? api.estimateTreeAge)(
          widget.scientificName,
          widget.dbhCm,
          widget.heightM,
          widget.dimensionsSource);
      if (mounted && request == _request) {
        setState(() => _result = result);
        widget.onEstimated?.call(result);
      }
    } catch (error) {
      if (mounted && request == _request) {
        setState(() {
          _failed = true;
          _failureMessage =
              error is DioException && error.response?.statusCode == 429
                  ? 'AI age estimation is temporarily busy. Try again later.'
                  : error is DioException && error.response?.statusCode == 401
                      ? 'Sign in again to estimate age.'
                      : 'Age estimate unavailable. Check your connection.';
        });
      }
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final estimated = _result?['status'] == 'estimated';
    final source = _result?['source'];
    final studyUri =
        source is Map ? Uri.tryParse(source['url']?.toString() ?? '') : null;
    final aiGrowth = _result?['estimation_basis'] == 'ai_growth_guess';
    final rates = _result?['growth_rates'];
    final dbhAge = ageDimension(_result?['dbh_age_years']);
    final heightAge = ageDimension(_result?['height_age_years']);
    final primaryAge = dbhAge ?? heightAge;
    final disagrees = _result?['dimensions_disagree'] == true;
    return Card(
      key: const Key('tree-age-card'),
      child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Estimated age',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              if (_loading)
                const Text('Checking growth data and estimating age…')
              else if (_failed) ...[
                Text(_failureMessage),
                TextButton(
                    onPressed: _load, child: const Text('Retry age estimate')),
              ] else ...[
                Text(
                    aiGrowth
                        ? 'AI growth estimate'
                        : source is Map
                            ? 'Published growth data'
                            : 'Growth data unavailable',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                    estimated && primaryAge != null
                        ? primaryAge < 1
                            ? 'Less than 1 year (estimated)'
                            : 'About ${primaryAge.round()} ${primaryAge.round() == 1 ? 'year' : 'years'} (estimated)'
                        : estimated
                            ? 'Approximately ${_result!['min_years']}–${_result!['max_years']} years'
                            : 'Age unknown',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold)),
                if (estimated && primaryAge != null)
                  Text(dbhAge != null
                      ? 'Estimated from trunk diameter (DBH).'
                      : 'Estimated from tree height.'),
                if (estimated && disagrees)
                  const Text(
                      'Height suggests a very different age. Treat this as a rough estimate.'),
                if (dbhAge != null || heightAge != null)
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Calculation details'),
                    children: [
                      if (dbhAge != null)
                        Text(
                            'From DBH: about ${_result!['dbh_age_years']} years'),
                      if (heightAge != null)
                        Text(
                            'From height: about ${_result!['height_age_years']} years'),
                      if (source is Map)
                        const Text(
                            'Uses average growth rates from the study. Individual trees can grow at different rates.'),
                      if (_result?['assumptions'] is String)
                        Text(_result!['assumptions'] as String),
                    ],
                  ),
                if (aiGrowth && estimated)
                  const Text(
                      'Uses AI-estimated growth rates. Growth varies with site and age.')
                else if (!estimated)
                  Text(_result?['reason']?.toString() ??
                      'No growth data available.'),
                if (rates is Map) ...[
                  if (rates['dbh_cm_per_year'] is List)
                    Text(
                        'Diameter growth: ${_rate(rates['dbh_cm_per_year'])} cm/year'),
                  if (rates['height_m_per_year'] is List)
                    Text(
                        'Height growth: ${_rate(rates['height_m_per_year'])} m/year'),
                ],
                if (aiGrowth && !estimated)
                  TextButton(
                      onPressed: _load,
                      child: const Text('Retry age estimate')),
                if (source is Map) ...[
                  const SizedBox(height: 8),
                  Text('Source: ${source['citation']}'),
                  Text(source['context']?.toString() ?? ''),
                  if (studyUri != null &&
                      studyUri.scheme == 'https' &&
                      studyUri.hasAuthority) ...[
                    TextButton(
                        onPressed: () async {
                          await Clipboard.setData(
                              ClipboardData(text: studyUri.toString()));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Study link copied. Open it in your browser.')));
                          }
                        },
                        child: const Text('Copy growth study link')),
                    SelectableText(studyUri.toString()),
                  ],
                ],
              ],
            ],
          )),
    );
  }

  String _rate(List values) {
    if (values.length != 3 || values.any((v) => v is! num)) {
      return 'Unavailable';
    }
    final low = (values.first as num).toStringAsFixed(2);
    final high = (values.last as num).toStringAsFixed(2);
    return low == high ? low : '$low–$high';
  }
}

double? ageDimension(dynamic value) {
  final number = value is num ? value.toDouble() : double.tryParse('$value');
  return number != null && number.isFinite && number > 0 ? number : null;
}

Map<String, dynamic>? savedAgeForTree(TreeModel tree) {
  if (tree.ageEstimate != null) return tree.ageEstimate;
  final scan = tree.scanProfile;
  if (scan == null || scan['scientific_name']?.toString().toLowerCase() != tree.scientificName?.toLowerCase() ||
      scan['estimated_dbh_cm'] != tree.dbhCm || scan['estimated_height_m'] != tree.heightM) return null;
  final age = scan['age_estimate'];
  return age is Map ? Map<String, dynamic>.from(age) : null;
}

class SavedScanDetails extends StatelessWidget {
  const SavedScanDetails({super.key, required this.tree});
  final TreeModel tree;
  @override
  Widget build(BuildContext context) {
    final facts = {...?tree.speciesProfile, ...speciesReferenceFacts(tree.scientificName)};
    final referenceResult = {...facts, 'scientific_name': tree.scientificName};
    final photos = curatedReferencePhotos(referenceResult);
    final score = tree.scanProfile?['confidence_percent'];
    final fields = {
      'Family': facts['family'], 'Overview': facts['description'],
      'Plant type': facts['plant_type'], 'Life span': facts['lifespan'],
      'Flowers': facts['flower'], 'Fruit': facts['fruit'],
      'Diagnostic features': facts['distinguishing_features'],
      'Similar species': facts['look_alikes'],
      'Explore — ecological uses': facts['uses'],
      'Explore — adaptation': facts['adaptation_strategies'],
      'Name story': facts['name_story'],
    };
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Species and scan details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        const Text('Original AI confidence', style: TextStyle(fontWeight: FontWeight.w600)),
        Text(score is num ? '${score.toStringAsFixed(2)}% — ${tree.scanProfile?['common_name'] ?? tree.scanProfile?['scientific_name'] ?? ''}'
          : 'Unavailable: no scan confidence was saved for this record.'),
        const Text('AI prediction score, separate from expert confirmation.', style: TextStyle(fontSize: 12)),
        if (photos.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('Species reference photos', style: TextStyle(fontWeight: FontWeight.w600)),
          SpeciesReferencePhotos(photos: photos.map((p) => Map<String, dynamic>.from(p)).toList()),
        ],
        if (speciesComparisons(referenceResult).isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('Similar species', style: TextStyle(fontWeight: FontWeight.w600)),
          SpeciesComparisons(result: referenceResult),
        ],
        for (final entry in fields.entries)
          if (entry.value is String && (entry.value as String).trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(entry.value as String, style: const TextStyle(height: 1.5)),
          ],
      ],
    )));
  }
}
